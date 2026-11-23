-- tests/test_regras.sql
-- Suite de testes da Fase 4: valida RS001..RS014, fluxo positivo, auditoria e taxa_ocupacao.
-- Roda dentro de uma transacao revertida (ROLLBACK) para nao alterar dados persistidos.

SET search_path = reservas, public;
SET timezone = 'America/Fortaleza';

BEGIN;

DO $$
DECLARE
  v_aluno1    bigint;
  v_aluno2    bigint;
  v_inativo   bigint;
  v_admin     bigint;
  v_sala      integer;
  v_sala_in   integer;
  v_res_ok    bigint;
  v_res_adm   bigint;
  v_res_pass  bigint;
  v_d_fut     date := current_date + 45;
  v_d_taxa    date := (date_trunc('month', (current_date + 90)::timestamp) + interval '5 days')::date;
  v_dias_mes  integer;
  v_taxa      numeric;
  v_esperada  numeric;
  v_op        text;
  v_old_st    text;
  v_new_st    text;
  v_cnt       integer;
BEGIN
  -- Massa isolada para nao depender nem interferir em dados preexistentes
  INSERT INTO usuario (matricula, nome, email, tipo, ativo)
  VALUES ('TR_ALUNO1', 'Aluno Regra 1', 'tr_a1@inst.edu.br', 'ALUNO', true)
  RETURNING id INTO v_aluno1;

  INSERT INTO usuario (matricula, nome, email, tipo, ativo)
  VALUES ('TR_ALUNO2', 'Aluno Regra 2', 'tr_a2@inst.edu.br', 'ALUNO', true)
  RETURNING id INTO v_aluno2;

  INSERT INTO usuario (matricula, nome, email, tipo, ativo)
  VALUES ('TR_INAT', 'Usuario Inativo', 'tr_inat@inst.edu.br', 'ALUNO', false)
  RETURNING id INTO v_inativo;

  INSERT INTO usuario (matricula, nome, email, tipo, ativo)
  VALUES ('TR_ADM', 'Admin Regra', 'tr_adm@inst.edu.br', 'ADMIN', true)
  RETURNING id INTO v_admin;

  INSERT INTO sala (codigo, nome, tipo, capacidade, ativa)
  VALUES ('TR-SALA1', 'Sala Teste Regras', 'SALA', 30, true)
  RETURNING id INTO v_sala;

  INSERT INTO sala (codigo, nome, tipo, capacidade, ativa)
  VALUES ('TR-INAT', 'Sala Inativa', 'SALA', 20, false)
  RETURNING id INTO v_sala_in;

  -- RS001: periodo invalido (fim <= inicio e nulo)
  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala,
      ((v_d_fut + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '09:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS001'
    );
    RAISE EXCEPTION 'FALHA RS001: aceitou fim <= inicio';
  EXCEPTION WHEN SQLSTATE 'RS001' THEN
    RAISE NOTICE 'OK RS001: periodo invalido rejeitado';
  END;

  -- RS002: reserva no passado
  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala,
      (((current_date - 2) + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      (((current_date - 2) + time '12:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS002'
    );
    RAISE EXCEPTION 'FALHA RS002: aceitou reserva no passado';
  EXCEPTION WHEN SQLSTATE 'RS002' THEN
    RAISE NOTICE 'OK RS002: reserva no passado rejeitada';
  END;

  -- RS003: usuario inexistente ou inativo
  BEGIN
    PERFORM criar_reserva(
      v_inativo, v_sala,
      ((v_d_fut + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS003'
    );
    RAISE EXCEPTION 'FALHA RS003: aceitou usuario inativo';
  EXCEPTION WHEN SQLSTATE 'RS003' THEN
    RAISE NOTICE 'OK RS003: usuario inativo/inexistente rejeitado';
  END;

  -- RS004: sala inexistente ou inativa
  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala_in,
      ((v_d_fut + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS004'
    );
    RAISE EXCEPTION 'FALHA RS004: aceitou sala inativa';
  EXCEPTION WHEN SQLSTATE 'RS004' THEN
    RAISE NOTICE 'OK RS004: sala inativa/inexistente rejeitada';
  END;

  -- RS005: duracao fora de [30 min, 4 h] (testa 15 min e 5 h)
  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala,
      ((v_d_fut + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '08:15')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS005 min'
    );
    RAISE EXCEPTION 'FALHA RS005 (min): aceitou duracao < 30 min';
  EXCEPTION WHEN SQLSTATE 'RS005' THEN
    NULL;
  END;

  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala,
      ((v_d_fut + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '13:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS005 max'
    );
    RAISE EXCEPTION 'FALHA RS005 (max): aceitou duracao > 4 h';
  EXCEPTION WHEN SQLSTATE 'RS005' THEN
    RAISE NOTICE 'OK RS005: duracao < 30min e > 4h rejeitadas';
  END;

  -- RS006: fora do horario (07:00-22:00) ou atravessando meia-noite
  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala,
      ((v_d_fut + time '06:30')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS006 cedo'
    );
    RAISE EXCEPTION 'FALHA RS006 (cedo): aceitou inicio antes das 07:00';
  EXCEPTION WHEN SQLSTATE 'RS006' THEN
    NULL;
  END;

  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala,
      ((v_d_fut + time '21:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      (((v_d_fut + 1) + time '00:30')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS006 meia-noite'
    );
    RAISE EXCEPTION 'FALHA RS006 (meia-noite): aceitou cruzar meia-noite';
  EXCEPTION WHEN SQLSTATE 'RS006' THEN
    RAISE NOTICE 'OK RS006: fora de 07:00-22:00 e cruzando meia-noite rejeitados';
  END;

  -- RS007: capacidade excedida (sala tem capacidade 30, tentando 31)
  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala,
      ((v_d_fut + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      31, 'RS007'
    );
    RAISE EXCEPTION 'FALHA RS007: aceitou qtd > capacidade';
  EXCEPTION WHEN SQLSTATE 'RS007' THEN
    RAISE NOTICE 'OK RS007: capacidade excedida rejeitada';
  END;

  -- Fluxo positivo + RS008: cria 3 reservas futuras para v_aluno1 e a 4a falha
  v_res_ok := criar_reserva(
    v_aluno1, v_sala,
    ((v_d_fut + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    ((v_d_fut + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    20, 'Reserva valida 1'
  );
  PERFORM criar_reserva(
    v_aluno1, v_sala,
    ((v_d_fut + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    ((v_d_fut + time '12:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    15, 'Reserva valida 2'
  );
  v_res_adm := criar_reserva(
    v_aluno1, v_sala,
    ((v_d_fut + time '14:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    ((v_d_fut + time '16:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    10, 'Reserva valida 3'
  );

  SELECT operacao, dados_novos->>'status' INTO v_op, v_new_st
    FROM log_reserva
   WHERE reserva_id = v_res_ok
   ORDER BY id DESC LIMIT 1;
  IF v_op <> 'INSERT' OR v_new_st <> 'ATIVA' THEN
    RAISE EXCEPTION 'FALHA auditoria INSERT: operacao=% status=%', v_op, v_new_st;
  END IF;
  RAISE NOTICE 'OK criacao e auditoria INSERT (id=%)', v_res_ok;

  -- Teste UPDATE comum gerando log UPDATE
  UPDATE reserva SET finalidade = 'Finalidade atualizada' WHERE id = v_res_ok;
  SELECT operacao INTO v_op FROM log_reserva WHERE reserva_id = v_res_ok ORDER BY id DESC LIMIT 1;
  IF v_op <> 'UPDATE' THEN
    RAISE EXCEPTION 'FALHA auditoria UPDATE: operacao=%', v_op;
  END IF;
  RAISE NOTICE 'OK auditoria UPDATE';

  -- RS008: 4a reserva futura do mesmo usuario
  BEGIN
    PERFORM criar_reserva(
      v_aluno1, v_sala,
      ((v_d_fut + time '16:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '18:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS008 4a reserva'
    );
    RAISE EXCEPTION 'FALHA RS008: aceitou 4a reserva futura';
  EXCEPTION WHEN SQLSTATE 'RS008' THEN
    RAISE NOTICE 'OK RS008: limite de 3 reservas futuras aplicado';
  END;

  -- RS010: conflito de horario com outro usuario via criar_reserva
  BEGIN
    PERFORM criar_reserva(
      v_aluno2, v_sala,
      ((v_d_fut + time '09:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      ((v_d_fut + time '11:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      10, 'RS010 conflito'
    );
    RAISE EXCEPTION 'FALHA RS010: aceitou conflito de horario';
  EXCEPTION WHEN SQLSTATE 'RS010' THEN
    RAISE NOTICE 'OK RS010: conflito de horario traduzido do 23P01';
  END;

  -- RS011: cancelar reserva inexistente
  BEGIN
    PERFORM cancelar_reserva(-999999, v_aluno1, 'Nao existe');
    RAISE EXCEPTION 'FALHA RS011: cancelou reserva inexistente';
  EXCEPTION WHEN SQLSTATE 'RS011' THEN
    RAISE NOTICE 'OK RS011: reserva inexistente rejeitada no cancelamento';
  END;

  -- RS012: cancelar reserva de outro usuario sem ser ADMIN
  BEGIN
    PERFORM cancelar_reserva(v_res_ok, v_aluno2, 'Tentativa indevida');
    RAISE EXCEPTION 'FALHA RS012: outro aluno conseguiu cancelar';
  EXCEPTION WHEN SQLSTATE 'RS012' THEN
    RAISE NOTICE 'OK RS012: usuario sem permissao impedido de cancelar';
  END;

  -- Cancelamento valido pelo dono + auditoria CANCELAMENTO
  PERFORM cancelar_reserva(v_res_ok, v_aluno1, 'Mudanca de plano');
  SELECT operacao, dados_antigos->>'status', dados_novos->>'status'
    INTO v_op, v_old_st, v_new_st
    FROM log_reserva
   WHERE reserva_id = v_res_ok
   ORDER BY id DESC LIMIT 1;
  IF v_op <> 'CANCELAMENTO' OR v_old_st <> 'ATIVA' OR v_new_st <> 'CANCELADA' THEN
    RAISE EXCEPTION 'FALHA auditoria CANCELAMENTO: op=% old=% new=%', v_op, v_old_st, v_new_st;
  END IF;
  RAISE NOTICE 'OK cancelamento pelo dono + auditoria CANCELAMENTO';

  -- Cancelamento valido por ADMIN
  PERFORM cancelar_reserva(v_res_adm, v_admin, 'Manutencao na sala');
  SELECT count(*) INTO v_cnt
    FROM log_reserva
   WHERE reserva_id = v_res_adm AND operacao = 'CANCELAMENTO';
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FALHA cancelamento por ADMIN';
  END IF;
  RAISE NOTICE 'OK cancelamento por ADMIN';

  -- RS013: cancelar reserva ja cancelada
  BEGIN
    PERFORM cancelar_reserva(v_res_ok, v_aluno1, 'Duplo cancelamento');
    RAISE EXCEPTION 'FALHA RS013: permitiu cancelar duas vezes';
  EXCEPTION WHEN SQLSTATE 'RS013' THEN
    RAISE NOTICE 'OK RS013: reserva ja cancelada rejeitada';
  END;

  -- RS009: tentar reativar reserva cancelada
  BEGIN
    UPDATE reserva SET status = 'ATIVA', cancelada_em = NULL WHERE id = v_res_ok;
    RAISE EXCEPTION 'FALHA RS009: permitiu reativar reserva cancelada';
  EXCEPTION WHEN SQLSTATE 'RS009' THEN
    RAISE NOTICE 'OK RS009: reativacao de reserva cancelada rejeitada';
  END;

  -- RS014: cancelar reserva ja iniciada (inserida no passado diretamente na tabela)
  INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade)
  VALUES (
    v_aluno2, v_sala,
    tstzrange(
      (((current_date - 1) + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      (((current_date - 1) + time '12:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
      '[)'
    ),
    10, 'Reserva passada para testar RS014'
  )
  RETURNING id INTO v_res_pass;

  BEGIN
    PERFORM cancelar_reserva(v_res_pass, v_aluno2, 'Tarde demais');
    RAISE EXCEPTION 'FALHA RS014: permitiu cancelar reserva ja iniciada';
  EXCEPTION WHEN SQLSTATE 'RS014' THEN
    RAISE NOTICE 'OK RS014: cancelamento de reserva ja iniciada rejeitado';
  END;

  -- Validacao de taxa_ocupacao(sala, mes) em mes isolado (3h exatas reservadas)
  PERFORM criar_reserva(
    v_aluno2, v_sala,
    ((v_d_taxa + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    ((v_d_taxa + time '11:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    10, 'Reserva para taxa_ocupacao'
  );
  v_dias_mes := (date_trunc('month', v_d_taxa::timestamp)::date + interval '1 month')::date
                - date_trunc('month', v_d_taxa::timestamp)::date;
  v_esperada := ROUND((3.0 / (v_dias_mes * 15.0)) * 100.0, 2);
  v_taxa     := taxa_ocupacao(v_sala, v_d_taxa);
  IF v_taxa <> v_esperada THEN
    RAISE EXCEPTION 'FALHA taxa_ocupacao: esperado % obtido %', v_esperada, v_taxa;
  END IF;
  RAISE NOTICE 'OK taxa_ocupacao = % %% (esperado % %%)', v_taxa, v_esperada;
END
$$;

ROLLBACK;
