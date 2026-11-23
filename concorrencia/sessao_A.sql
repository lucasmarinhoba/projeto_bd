-- concorrencia/sessao_A.sql
-- Cenario 1 (Terminal 1 - Sessao A): abre transacao e reserva a sala 5 das 14h as 16h.
-- Execute linha a linha manualmente para observar o bloqueio da Sessao B.

SET search_path = reservas, public;
SET timezone = 'America/Fortaleza';

BEGIN;

SELECT criar_reserva(
  1,
  5,
  ((current_date + 10) + time '14:00')::timestamp AT TIME ZONE 'America/Fortaleza',
  ((current_date + 10) + time '16:00')::timestamp AT TIME ZONE 'America/Fortaleza',
  20,
  'Sessao A (14h-16h)'
);

-- PARE AQUI antes de continuar e execute concorrencia/sessao_B.sql no Terminal 2!
-- Enquanto Sessao B estiver bloqueada, consulte pg_stat_activity no Terminal 3 (Sessao C).
--
-- Depois escolha uma das duas variantes finais:
--   Variante 5a (conflito confirmado):   COMMIT;
--   Variante 5b (horario liberado):      ROLLBACK;
