-- tests/test_seguranca.sql
-- Suite de testes da Fase 10: deve ser executada conectada COMO app_reservas.
-- Valida o principio do menor privilegio (apenas SELECT em views e EXECUTE nas 3 functions).

BEGIN;

DO $$
DECLARE
  v_tbl   text;
  v_vw    text;
  v_id    bigint;
  v_taxa  numeric;
  v_cnt   bigint;
  v_d_fut date := current_date + 25;
BEGIN
  IF session_user <> 'app_reservas' OR current_user <> 'app_reservas' THEN
    RAISE EXCEPTION 'FALHA: test_seguranca.sql deve rodar como app_reservas (atual=%)', current_user;
  END IF;
  RAISE NOTICE 'OK sessao autenticada como app_reservas';

  -- 1) Conferencia declarativa: ZERO privilegios diretos nas 6 tabelas
  FOREACH v_tbl IN ARRAY ARRAY['usuario', 'sala', 'recurso', 'sala_recurso', 'reserva', 'log_reserva'] LOOP
    IF has_table_privilege('app_reservas', 'reservas.' || v_tbl, 'SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION 'FALHA: app_reservas tem privilegio direto na tabela %', v_tbl;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK declarativo: zero privilegios diretos nas 6 tabelas base';

  -- 2) Conferencia declarativa: sem CREATE no schema reservas
  IF has_schema_privilege('app_reservas', 'reservas', 'CREATE') THEN
    RAISE EXCEPTION 'FALHA: app_reservas tem CREATE no schema reservas';
  END IF;
  RAISE NOTICE 'OK declarativo: sem CREATE no schema reservas';

  -- 3) Conferencia declarativa: SELECT nas views e EXECUTE somente nas 3 functions da API
  FOREACH v_vw IN ARRAY ARRAY['v_agenda_dia', 'v_reservas_usuario', 'mv_ocupacao_mensal', 'v_salas_recursos'] LOOP
    IF NOT has_table_privilege('app_reservas', 'reservas.' || v_vw, 'SELECT') THEN
      RAISE EXCEPTION 'FALHA: app_reservas nao tem SELECT em %', v_vw;
    END IF;
  END LOOP;

  IF NOT has_function_privilege('app_reservas', 'reservas.criar_reserva(bigint,integer,timestamptz,timestamptz,integer,text)', 'EXECUTE')
     OR NOT has_function_privilege('app_reservas', 'reservas.cancelar_reserva(bigint,bigint,text)', 'EXECUTE')
     OR NOT has_function_privilege('app_reservas', 'reservas.taxa_ocupacao(integer,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FALHA: falta EXECUTE em alguma function da API';
  END IF;

  IF has_function_privilege('app_reservas', 'reservas.fn_audit_reserva()', 'EXECUTE')
     OR has_function_privilege('app_reservas', 'reservas.fn_regras_reserva()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FALHA: app_reservas tem EXECUTE nas trigger functions internas';
  END IF;
  RAISE NOTICE 'OK declarativo: SELECT nas 4 views e EXECUTE apenas nas 3 functions da API';

  -- 4) Tentativas reais bloqueadas (devem falhar com SQLSTATE 42501 / insufficient_privilege)
  BEGIN
    PERFORM * FROM reservas.reserva LIMIT 1;
    RAISE EXCEPTION 'FALHA: conseguiu SELECT em reserva';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK bloqueio: SELECT em reserva negado (42501)';
  END;

  BEGIN
    INSERT INTO reservas.reserva (usuario_id, sala_id, periodo, qtd_participantes)
    VALUES (1, 5, tstzrange(now() + interval '1 day', now() + interval '1 day 1 hour', '[)'), 5);
    RAISE EXCEPTION 'FALHA: conseguiu INSERT direto em reserva';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK bloqueio: INSERT direto em reserva negado (42501)';
  END;

  BEGIN
    UPDATE reservas.sala SET ativa = false WHERE id = 1;
    RAISE EXCEPTION 'FALHA: conseguiu UPDATE direto em sala';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK bloqueio: UPDATE direto em tabelas negado (42501)';
  END;

  BEGIN
    DELETE FROM reservas.usuario WHERE id = 1;
    RAISE EXCEPTION 'FALHA: conseguiu DELETE direto em usuario';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK bloqueio: DELETE direto em tabelas negado (42501)';
  END;

  BEGIN
    PERFORM * FROM reservas.log_reserva LIMIT 1;
    RAISE EXCEPTION 'FALHA: conseguiu SELECT em log_reserva';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK bloqueio: SELECT em log_reserva negado (42501)';
  END;

  BEGIN
    CREATE TABLE reservas.tabela_indevida (id int);
    RAISE EXCEPTION 'FALHA: conseguiu CREATE TABLE no schema reservas';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK bloqueio: CREATE TABLE no schema reservas negado (42501)';
  END;

  -- 5) Tentativas reais permitidas (views + criar_reserva + cancelar_reserva + taxa_ocupacao)
  SELECT count(*) INTO v_cnt FROM v_agenda_dia;
  SELECT count(*) INTO v_cnt FROM v_reservas_usuario;
  SELECT count(*) INTO v_cnt FROM mv_ocupacao_mensal;
  SELECT count(*) INTO v_cnt FROM v_salas_recursos;

  v_id := criar_reserva(
    1, 5,
    ((v_d_fut + time '09:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    ((v_d_fut + time '11:00')::timestamp AT TIME ZONE 'America/Fortaleza'),
    15, 'Teste seguranca app_reservas'
  );
  PERFORM cancelar_reserva(v_id, 1, 'Limpeza teste seguranca');
  v_taxa := taxa_ocupacao(1, current_date);

  IF v_id IS NULL OR v_taxa IS NULL THEN
    RAISE EXCEPTION 'FALHA: retorno nulo em funcao permitida';
  END IF;
  RAISE NOTICE 'OK permissoes: views, criar_reserva (id=%), cancelar_reserva e taxa_ocupacao (% %%) executam como app_reservas', v_id, v_taxa;
END
$$;

ROLLBACK;
