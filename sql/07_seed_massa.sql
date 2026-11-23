-- sql/07_seed_massa.sql
-- Carga massiva (>= 12.000 reservas) livre de conflitos por construcao,
-- mantendo triggers de regras/auditoria e constraint EXCLUDE totalmente ativos.

SET search_path = reservas, public;
SET timezone = 'America/Fortaleza';

SELECT setseed(0.42);

-- =============================================================================
-- 1. Historico dos ultimos 365 dias (~12.700 reservas em slots disjuntos)
-- =============================================================================
WITH slots(h) AS (
  VALUES (7), (9), (11), (13), (15), (17), (19)
),
dias AS (
  SELECT d::date AS dia
  FROM generate_series(current_date - 365, current_date - 1, interval '1 day') AS d
),
u AS (
  SELECT array_agg(id ORDER BY id) AS ids
  FROM usuario
  WHERE ativo AND tipo <> 'ADMIN'
),
cand AS MATERIALIZED (
  -- AS MATERIALIZED impede o planner de reavaliar random() a cada referencia
  SELECT
    s.id AS sala_id,
    s.capacidade,
    d.dia,
    sl.h,
    (ARRAY[60, 90, 120])[1 + floor(random() * 3)::int] AS dur_min,
    random() AS r_sel,
    random() AS r_usr,
    random() AS r_qtd,
    random() AS r_ant,
    random() AS r_fin
  FROM sala s
  CROSS JOIN dias d
  CROSS JOIN slots sl
  WHERE s.ativa
)
INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade, criada_em)
SELECT
  u.ids[LEAST(1 + floor(c.r_usr * array_length(u.ids, 1))::int, array_length(u.ids, 1))],
  c.sala_id,
  tstzrange(t.ini, t.ini + make_interval(mins => c.dur_min), '[)'),
  LEAST(1 + floor(c.r_qtd * c.capacidade)::int, c.capacidade),
  (ARRAY[
    'Aula pratica',
    'Monitoria',
    'Reuniao de grupo',
    'Seminario',
    'Estudo dirigido',
    'Projeto de pesquisa'
  ])[LEAST(1 + floor(c.r_fin * 6)::int, 6)],
  t.ini - make_interval(days => 1 + floor(c.r_ant * 14)::int)
FROM cand c
CROSS JOIN u
CROSS JOIN LATERAL (
  SELECT ((c.dia + make_interval(hours => c.h))::timestamp AT TIME ZONE 'America/Fortaleza') AS ini
) AS t
WHERE c.r_sel < 0.25;

-- =============================================================================
-- 2. Reservas futuras (~120 reservas nos proximos 30 dias, <= 3 por usuario)
-- Exclui sala 5 (demo) e usuarios 1..4 (demo) para nao interferir na Fase 9/11.
-- =============================================================================
WITH slots(h) AS (
  VALUES (8), (10), (14), (16), (18)
),
dias_fut AS (
  SELECT d::date AS dia
  FROM generate_series(current_date + 1, current_date + 30, interval '1 day') AS d
),
u_fut AS (
  SELECT array_agg(id ORDER BY id) AS ids
  FROM usuario
  WHERE ativo AND tipo <> 'ADMIN' AND id NOT IN (1, 2, 3, 4)
),
cand_fut AS MATERIALIZED (
  SELECT
    s.id AS sala_id,
    s.capacidade,
    d.dia,
    sl.h,
    (ARRAY[60, 120])[1 + floor(random() * 2)::int] AS dur_min,
    random() AS r_ord,
    random() AS r_qtd
  FROM sala s
  CROSS JOIN dias_fut d
  CROSS JOIN slots sl
  WHERE s.ativa AND s.id <> 5
),
escolhidas AS (
  SELECT *, row_number() OVER (ORDER BY r_ord) AS rn
  FROM cand_fut
  ORDER BY r_ord
  LIMIT 120
)
INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade, criada_em)
SELECT
  u_fut.ids[1 + ((e.rn - 1) % array_length(u_fut.ids, 1))],
  e.sala_id,
  tstzrange(t.ini, t.ini + make_interval(mins => e.dur_min), '[)'),
  LEAST(1 + floor(e.r_qtd * e.capacidade)::int, e.capacidade),
  'Reserva futura agendada (seed)',
  now() - interval '1 day'
FROM escolhidas e
CROSS JOIN u_fut
CROSS JOIN LATERAL (
  SELECT ((e.dia + make_interval(hours => e.h))::timestamp AT TIME ZONE 'America/Fortaleza') AS ini
) AS t;

-- =============================================================================
-- 3. Cancelamentos (~8% da carga) -> popula log_reserva com CANCELAMENTO
-- =============================================================================
UPDATE reserva
   SET status = 'CANCELADA',
       cancelada_em = LEAST(now(), lower(periodo) - interval '2 hours'),
       motivo_cancelamento = 'Cancelamento simulado no seed massivo'
 WHERE random() < 0.08;

-- =============================================================================
-- 4. Atualizar materialized view e estatisticas do otimizador
-- =============================================================================
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ocupacao_mensal;
ANALYZE usuario;
ANALYZE sala;
ANALYZE recurso;
ANALYZE sala_recurso;
ANALYZE reserva;
ANALYZE log_reserva;
ANALYZE mv_ocupacao_mensal;
