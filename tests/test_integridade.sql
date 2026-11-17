-- tests/test_integridade.sql
-- Suite de testes da Fase 2: valida ENUMs, DOMAINs, CHECKs, UNIQUE, FK ON DELETE e EXCLUDE USING gist.
-- Roda dentro de uma transacao revertida ao final (ROLLBACK) para nao deixar dados de teste no banco.

SET search_path = reservas, public;
SET timezone = 'America/Fortaleza';

BEGIN;

DO $$
DECLARE
  v_u1      bigint;
  v_u2      bigint;
  v_s1      integer;
  v_s_vazia integer;
  v_rec     integer;
  v_d       date := current_date + 40;
  v_t08     timestamptz := ((v_d + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza');
  v_t09     timestamptz := ((v_d + time '09:00')::timestamp AT TIME ZONE 'America/Fortaleza');
  v_t10     timestamptz := ((v_d + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza');
  v_t11     timestamptz := ((v_d + time '11:00')::timestamp AT TIME ZONE 'America/Fortaleza');
  v_t12     timestamptz := ((v_d + time '12:00')::timestamp AT TIME ZONE 'America/Fortaleza');
  v_t13     timestamptz := ((v_d + time '13:00')::timestamp AT TIME ZONE 'America/Fortaleza');
  v_t15     timestamptz := ((v_d + time '15:00')::timestamp AT TIME ZONE 'America/Fortaleza');
  v_cnt     integer;
BEGIN
  -- Massa temporaria isolada (sem depender do seed da Fase 3)
  INSERT INTO usuario (matricula, nome, email, tipo)
  VALUES ('TEST_MAT_01', 'Usuario Teste 1', 'teste1@inst.edu.br', 'ALUNO')
  RETURNING id INTO v_u1;

  INSERT INTO usuario (matricula, nome, email, tipo)
  VALUES ('TEST_MAT_02', 'Usuario Teste 2', 'teste2@inst.edu.br', 'ALUNO')
  RETURNING id INTO v_u2;

  INSERT INTO sala (codigo, nome, tipo, capacidade)
  VALUES ('TEST-S1', 'Sala Teste 1', 'SALA', 40)
  RETURNING id INTO v_s1;

  INSERT INTO sala (codigo, nome, tipo, capacidade)
  VALUES ('TEST-S2', 'Sala Teste Sem Reserva', 'SALA', 25)
  RETURNING id INTO v_s_vazia;

  INSERT INTO recurso (nome)
  VALUES ('Recurso Teste Integr')
  RETURNING id INTO v_rec;

  INSERT INTO sala_recurso (sala_id, recurso_id, quantidade)
  VALUES (v_s_vazia, v_rec, 2);

  -- 1) E-mail invalido (violacao do DOMAIN email_t -> SQLSTATE 23514)
  BEGIN
    INSERT INTO usuario (matricula, nome, email, tipo)
    VALUES ('TEST_MAT_ERR', 'Email Invalido', 'invalido-sem-arroba', 'ALUNO');
    RAISE EXCEPTION 'FALHA 1: aceitou e-mail invalido';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK 1: e-mail invalido bloqueado pelo DOMAIN email_t (23514)';
  END;

  -- 2) Capacidade = 0 (violacao do DOMAIN qtd_positiva -> SQLSTATE 23514)
  BEGIN
    INSERT INTO sala (codigo, nome, tipo, capacidade)
    VALUES ('TEST-CAP0', 'Sala Zero', 'SALA', 0);
    RAISE EXCEPTION 'FALHA 2: aceitou capacidade = 0';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK 2: capacidade = 0 bloqueada pelo DOMAIN qtd_positiva (23514)';
  END;

  -- 3) Matricula duplicada (UNIQUE -> SQLSTATE 23505)
  BEGIN
    INSERT INTO usuario (matricula, nome, email, tipo)
    VALUES ('TEST_MAT_01', 'Duplicado', 'outro@inst.edu.br', 'ALUNO');
    RAISE EXCEPTION 'FALHA 3: aceitou matricula duplicada';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK 3: matricula duplicada bloqueada por UNIQUE (23505)';
  END;

  -- 4a) Periodo vazio (CHECK ck_periodo_valido -> SQLSTATE 23514)
  BEGIN
    INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes)
    VALUES (v_u1, v_s1, 'empty'::tstzrange, 10);
    RAISE EXCEPTION 'FALHA 4a: aceitou periodo vazio';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK 4a: periodo vazio bloqueado por ck_periodo_valido (23514)';
  END;

  -- 4b) Periodo infinito (CHECK ck_periodo_valido -> SQLSTATE 23514)
  BEGIN
    INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes)
    VALUES (v_u1, v_s1, tstzrange(v_t08, NULL, '[)'), 10);
    RAISE EXCEPTION 'FALHA 4b: aceitou periodo infinito';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK 4b: periodo infinito bloqueado por ck_periodo_valido (23514)';
  END;

  -- 4c) Periodo fechado nos dois extremos [] (CHECK ck_periodo_valido -> SQLSTATE 23514)
  BEGIN
    INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes)
    VALUES (v_u1, v_s1, tstzrange(v_t08, v_t10, '[]'), 10);
    RAISE EXCEPTION 'FALHA 4c: aceitou periodo fechado []';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK 4c: periodo fechado [] bloqueado por ck_periodo_valido (23514)';
  END;

  -- 5) status='CANCELADA' sem cancelada_em (CHECK ck_cancelamento_coerente -> SQLSTATE 23514)
  BEGIN
    INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, status, cancelada_em)
    VALUES (v_u1, v_s1, tstzrange(v_t08, v_t10, '[)'), 10, 'CANCELADA', NULL);
    RAISE EXCEPTION 'FALHA 5: aceitou CANCELADA sem cancelada_em';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK 5: CANCELADA sem cancelada_em bloqueada por ck_cancelamento_coerente (23514)';
  END;

  -- 6) Duas reservas ATIVAS sobrepostas na mesma sala (EXCLUDE -> SQLSTATE 23P01)
  INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade)
  VALUES (v_u1, v_s1, tstzrange(v_t08, v_t10, '[)'), 10, 'Reserva base 08-10');

  BEGIN
    INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade)
    VALUES (v_u2, v_s1, tstzrange(v_t09, v_t11, '[)'), 10, 'Conflito 09-11');
    RAISE EXCEPTION 'FALHA 6: aceitou reservas sobrepostas na mesma sala';
  EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'OK 6: sobreposicao de reservas ATIVAS bloqueada por EXCLUDE sem_conflito (23P01)';
  END;

  -- 7) Reserva ATIVA sobreposta a uma CANCELADA deve ser ACEITA
  INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, status, cancelada_em, finalidade)
  VALUES (v_u1, v_s1, tstzrange(v_t13, v_t15, '[)'), 10, 'CANCELADA', now(), 'Cancelada 13-15');

  INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade)
  VALUES (v_u1, v_s1, tstzrange(v_t13, v_t15, '[)'), 10, 'Ativa sobre cancelada 13-15');
  RAISE NOTICE 'OK 7: reserva ATIVA sobreposta a uma CANCELADA foi aceita';

  -- 8) Reservas adjacentes 08:00-10:00 e 10:00-12:00 (outra data, ou 10-12 na mesma sala apos 08-10)
  -- Como v_s1 ja tem 08-10 no dia v_d, inserir 10:00-12:00 testa exatamente a fronteira [)
  INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade)
  VALUES (v_u2, v_s1, tstzrange(v_t10, v_t12, '[)'), 10, 'Adjacente 10-12');
  RAISE NOTICE 'OK 8: reserva adjacente 10:00-12:00 apos 08:00-10:00 aceita pelo intervalo [)';

  -- 9) Verificacao de ON DELETE RESTRICT (sala com reserva) e CASCADE (sala_recurso)
  BEGIN
    DELETE FROM sala WHERE id = v_s1;
    RAISE EXCEPTION 'FALHA 9a: permitiu apagar sala com reserva';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK 9a: ON DELETE RESTRICT impediu apagar sala com reserva (23503)';
  END;

  DELETE FROM sala WHERE id = v_s_vazia;
  SELECT count(*) INTO v_cnt FROM sala_recurso WHERE sala_id = v_s_vazia;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FALHA 9b: CASCADE nao removeu sala_recurso';
  END IF;
  RAISE NOTICE 'OK 9b: ON DELETE CASCADE removeu associacoes em sala_recurso ao apagar sala sem reserva';
END
$$;

ROLLBACK;
