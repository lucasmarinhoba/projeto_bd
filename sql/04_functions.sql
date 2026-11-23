-- sql/04_functions.sql
-- Interface programatica do banco: criar_reserva, cancelar_reserva e taxa_ocupacao.

SET search_path = reservas, public;
SET ROLE reservas_owner;

-- =============================================================================
-- 1. criar_reserva: valida pre-condicoes, insere (dispara triggers) e traduz 23P01
-- =============================================================================
CREATE OR REPLACE FUNCTION criar_reserva(
  p_usuario_id bigint,
  p_sala_id    integer,
  p_inicio     timestamptz,
  p_fim        timestamptz,
  p_qtd        integer,
  p_finalidade text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = reservas, pg_temp
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF p_inicio IS NULL OR p_fim IS NULL OR p_fim <= p_inicio THEN
    RAISE EXCEPTION 'Periodo invalido: o fim deve ser posterior ao inicio.'
      USING ERRCODE = 'RS001';
  END IF;

  IF p_inicio < now() THEN
    RAISE EXCEPTION 'Nao e possivel reservar um horario que ja passou.'
      USING ERRCODE = 'RS002';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM usuario WHERE id = p_usuario_id AND ativo) THEN
    RAISE EXCEPTION 'Usuario % inexistente ou inativo.', p_usuario_id
      USING ERRCODE = 'RS003';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM sala WHERE id = p_sala_id AND ativa) THEN
    RAISE EXCEPTION 'Sala % inexistente ou inativa.', p_sala_id
      USING ERRCODE = 'RS004';
  END IF;

  INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade)
  VALUES (p_usuario_id, p_sala_id, tstzrange(p_inicio, p_fim, '[)'), p_qtd, p_finalidade)
  RETURNING id INTO v_id;

  RETURN v_id;
EXCEPTION
  WHEN exclusion_violation THEN -- 23P01 disparado pela constraint sem_conflito
    RAISE EXCEPTION 'Conflito de horario: a sala % ja esta reservada em parte do periodo pedido.',
      p_sala_id
      USING ERRCODE = 'RS010';
END;
$$;

COMMENT ON FUNCTION criar_reserva(bigint, integer, timestamptz, timestamptz, integer, text) IS
  'Cria reserva validando periodo/passado/cadastros (RS001-RS004), dispara trg_regras_reserva (RS005-RS008) e traduz 23P01 para RS010.';

-- =============================================================================
-- 2. cancelar_reserva: valida existencia, status, inicio e permissao (dono ou ADMIN)
-- =============================================================================
CREATE OR REPLACE FUNCTION cancelar_reserva(
  p_reserva_id bigint,
  p_usuario_id bigint,
  p_motivo     text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = reservas, pg_temp
AS $$
DECLARE
  v_res      reserva%ROWTYPE;
  v_is_admin boolean;
BEGIN
  -- FOR UPDATE serializa cancelamentos concorrentes na mesma reserva.
  SELECT * INTO v_res
    FROM reserva
   WHERE id = p_reserva_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reserva % nao encontrada.', p_reserva_id
      USING ERRCODE = 'RS011';
  END IF;

  IF v_res.status = 'CANCELADA' THEN
    RAISE EXCEPTION 'A reserva % ja foi cancelada anteriormente.', p_reserva_id
      USING ERRCODE = 'RS013';
  END IF;

  IF lower(v_res.periodo) <= now() THEN
    RAISE EXCEPTION 'Nao e possivel cancelar a reserva % porque ela ja foi iniciada.', p_reserva_id
      USING ERRCODE = 'RS014';
  END IF;

  SELECT (tipo = 'ADMIN' AND ativo) INTO v_is_admin
    FROM usuario
   WHERE id = p_usuario_id;

  IF v_res.usuario_id <> p_usuario_id AND NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Usuario % nao tem permissao para cancelar a reserva %.',
      p_usuario_id, p_reserva_id
      USING ERRCODE = 'RS012';
  END IF;

  UPDATE reserva
     SET status = 'CANCELADA',
         cancelada_em = now(),
         motivo_cancelamento = p_motivo
   WHERE id = p_reserva_id;
END;
$$;

COMMENT ON FUNCTION cancelar_reserva(bigint, bigint, text) IS
  'Cancela reserva futura mediante autorizacao (dono ou ADMIN ativo), registrando log CANCELAMENTO via trigger.';

-- =============================================================================
-- 3. taxa_ocupacao: percentual mensal de horas ATIVAS sobre (dias do mes * 15h)
-- =============================================================================
CREATE OR REPLACE FUNCTION taxa_ocupacao(
  p_sala_id integer,
  p_mes     date
) RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = reservas, pg_temp
AS $$
DECLARE
  c_tz          constant text    := 'America/Fortaleza';
  c_horas_dia   constant numeric := 15.0; -- 07:00 as 22:00
  v_mes_ini     date;
  v_mes_fim     date;
  v_dias        integer;
  v_ini_tz      timestamptz;
  v_fim_tz      timestamptz;
  v_horas       numeric;
BEGIN
  IF p_sala_id IS NULL OR NOT EXISTS (SELECT 1 FROM sala WHERE id = p_sala_id) THEN
    RAISE EXCEPTION 'Sala % inexistente.', p_sala_id
      USING ERRCODE = 'RS004';
  END IF;

  IF p_mes IS NULL THEN
    RAISE EXCEPTION 'Mes de referencia invalido (nulo).'
      USING ERRCODE = 'RS001';
  END IF;

  -- date_trunc com timestamp evita deslocamento de fuso ao converter date.
  v_mes_ini := date_trunc('month', p_mes::timestamp)::date;
  v_mes_fim := (v_mes_ini + interval '1 month')::date;
  v_dias    := v_mes_fim - v_mes_ini;
  v_ini_tz  := (v_mes_ini::timestamp AT TIME ZONE c_tz);
  v_fim_tz  := (v_mes_fim::timestamp AT TIME ZONE c_tz);

  SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (upper(periodo) - lower(periodo))) / 3600.0), 0)
    INTO v_horas
    FROM reserva
   WHERE sala_id = p_sala_id
     AND status = 'ATIVA'
     AND lower(periodo) >= v_ini_tz
     AND lower(periodo) < v_fim_tz;

  RETURN ROUND((v_horas / (v_dias * c_horas_dia)) * 100.0, 2);
END;
$$;

COMMENT ON FUNCTION taxa_ocupacao(integer, date) IS
  'Calcula a taxa de ocupacao (%) de uma sala no mes informado, coerente com mv_ocupacao_mensal.';

RESET ROLE;
