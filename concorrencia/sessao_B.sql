-- concorrencia/sessao_B.sql
-- Cenario 1 (Terminal 2 - Sessao B): tenta reservar a mesma sala 5 das 15h as 17h (sobrepoe 15h-16h).
-- Deve ser executado apos o SELECT criar_reserva(...) da Sessao A e ANTES do COMMIT/ROLLBACK dela.

SET search_path = reservas, public;
SET timezone = 'America/Fortaleza';

BEGIN;

SELECT criar_reserva(
  2,
  5,
  ((current_date + 10) + time '15:00')::timestamp AT TIME ZONE 'America/Fortaleza',
  ((current_date + 10) + time '17:00')::timestamp AT TIME ZONE 'America/Fortaleza',
  10,
  'Sessao B (15h-17h)'
);

-- A Sessao B ficara BLOQUEADA aqui ate a Sessao A executar COMMIT ou ROLLBACK.
--
-- No Terminal 3 (Sessao C), execute para ver o bloqueio ao vivo:
--   SELECT pid, state, wait_event_type, wait_event, left(query, 60) AS query
--   FROM pg_stat_activity
--   WHERE datname = current_database() AND pid <> pg_backend_pid();
--
-- Se Sessao A fez COMMIT -> esta sessao falha com RS010; finalize com ROLLBACK;
-- Se Sessao A fez ROLLBACK -> esta sessao retorna o id da reserva; finalize com COMMIT;
