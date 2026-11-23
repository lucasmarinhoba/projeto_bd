-- sql/03_triggers.sql
-- Triggers de auditoria (AFTER) e regras de negocio (BEFORE) na tabela reserva.

SET search_path = reservas, public;
SET ROLE reservas_owner;

-- =============================================================================
-- 1. Trigger de auditoria (AFTER INSERT OR UPDATE FOR EACH ROW)
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_audit_reserva() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = reservas, pg_temp
AS $$
DECLARE
  v_op text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO log_reserva (reserva_id, operacao, dados_novos)
    VALUES (NEW.id, 'INSERT', to_jsonb(NEW));
  ELSE
    v_op := CASE
      WHEN OLD.status = 'ATIVA' AND NEW.status = 'CANCELADA' THEN 'CANCELAMENTO'
      ELSE 'UPDATE'
    END;
    INSERT INTO log_reserva (reserva_id, operacao, dados_antigos, dados_novos)
    VALUES (NEW.id, v_op, to_jsonb(OLD), to_jsonb(NEW));
  END IF;

  RETURN NULL; -- valor ignorado em trigger AFTER
END;
$$;

COMMENT ON FUNCTION fn_audit_reserva() IS
  'Registra INSERT, UPDATE e CANCELAMENTO em log_reserva com snapshots jsonb de OLD e NEW.';

CREATE TRIGGER trg_audit_reserva
  AFTER INSERT OR UPDATE ON reserva
  FOR EACH ROW
  EXECUTE FUNCTION fn_audit_reserva();

COMMENT ON TRIGGER trg_audit_reserva ON reserva IS
  'Auditoria AFTER para garantir que so operacoes efetivadas entrem em log_reserva.';

-- =============================================================================
-- 2. Trigger de regras de negocio (BEFORE INSERT OR UPDATE FOR EACH ROW)
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_regras_reserva() RETURNS trigger
LANGUAGE plpgsql
SET search_path = reservas, pg_temp
AS $$
DECLARE
  c_tz          constant text     := 'America/Fortaleza';
  c_abre        constant time     := '07:00';
  c_fecha       constant time     := '22:00';
  c_dur_min     constant interval := interval '30 minutes';
  c_dur_max     constant interval := interval '4 hours';
  c_max_futuras constant integer  := 3;

  v_cap integer;
  v_qtd integer;
  v_ini timestamp;
  v_fim timestamp;
  v_dur interval;
BEGIN
  -- 1) Reserva cancelada nao pode ser reativada (RS009)
  IF TG_OP = 'UPDATE' AND OLD.status = 'CANCELADA' AND NEW.status <> 'CANCELADA' THEN
    RAISE EXCEPTION 'A reserva % ja foi cancelada e nao pode ser reativada.', OLD.id
      USING ERRCODE = 'RS009';
  END IF;

  -- 2) Regras de agendamento valem apenas para reservas ATIVAS com limites validos
  --    (periodos vazios/infinitos seguem para serem barrados por ck_periodo_valido)
  IF NEW.status <> 'ATIVA'
     OR NEW.periodo IS NULL
     OR isempty(NEW.periodo)
     OR lower_inf(NEW.periodo)
     OR upper_inf(NEW.periodo) THEN
    RETURN NEW;
  END IF;

  v_ini := lower(NEW.periodo) AT TIME ZONE c_tz;
  v_fim := upper(NEW.periodo) AT TIME ZONE c_tz;
  v_dur := upper(NEW.periodo) - lower(NEW.periodo);

  -- 3) Duracao minima e maxima (RS005)
  IF v_dur < c_dur_min OR v_dur > c_dur_max THEN
    RAISE EXCEPTION 'Duracao invalida (%). A reserva deve durar entre % e %.',
      v_dur, c_dur_min, c_dur_max
      USING ERRCODE = 'RS005';
  END IF;

  -- 4) Horario de funcionamento e mesmo dia local (RS006)
  IF v_ini::date <> v_fim::date OR v_ini::time < c_abre OR v_fim::time > c_fecha THEN
    RAISE EXCEPTION 'Fora do horario de funcionamento (% - %) ou atravessa a meia-noite.',
      c_abre, c_fecha
      USING ERRCODE = 'RS006';
  END IF;

  -- 5) Capacidade maxima da sala (RS007)
  SELECT capacidade INTO v_cap FROM sala WHERE id = NEW.sala_id;
  IF v_cap IS NOT NULL AND NEW.qtd_participantes > v_cap THEN
    RAISE EXCEPTION 'Capacidade excedida: a sala comporta % pessoas e foram informadas %.',
      v_cap, NEW.qtd_participantes
      USING ERRCODE = 'RS007';
  END IF;

  -- 6) Limite de reservas ativas futuras por usuario (RS008), serializado por usuario
  IF lower(NEW.periodo) > now() THEN
    -- FOR NO KEY UPDATE evita write skew entre sessoes sem bloquear checagens de FK (FOR KEY SHARE).
    PERFORM 1 FROM usuario WHERE id = NEW.usuario_id FOR NO KEY UPDATE;

    SELECT count(*) INTO v_qtd
      FROM reserva
     WHERE usuario_id = NEW.usuario_id
       AND status = 'ATIVA'
       AND lower(periodo) > now()
       AND id IS DISTINCT FROM NEW.id;

    IF v_qtd >= c_max_futuras THEN
      RAISE EXCEPTION 'Limite atingido: o usuario ja possui % reservas futuras ativas (maximo %).',
        v_qtd, c_max_futuras
        USING ERRCODE = 'RS008';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_regras_reserva() IS
  'Valida reativacao (RS009), duracao (RS005), horario local/dia unico (RS006), capacidade (RS007) e limite de futuras com lock (RS008).';

CREATE TRIGGER trg_regras_reserva
  BEFORE INSERT OR UPDATE ON reserva
  FOR EACH ROW
  EXECUTE FUNCTION fn_regras_reserva();

COMMENT ON TRIGGER trg_regras_reserva ON reserva IS
  'Aplica regras de negocio antes de gravar, independente do caminho de escrita (function, SQL direto ou seed).';

RESET ROLE;
