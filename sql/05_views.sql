-- sql/05_views.sql
-- Views de leitura para a aplicacao e materialized view de ocupacao mensal.

SET search_path = reservas, public;
SET ROLE reservas_owner;

-- =============================================================================
-- 1. v_agenda_dia: agenda de reservas ATIVAS por sala e dia local
-- =============================================================================
CREATE OR REPLACE VIEW v_agenda_dia AS
SELECT
  s.id                                                      AS sala_id,
  s.codigo                                                  AS sala_codigo,
  s.nome                                                    AS sala_nome,
  (lower(r.periodo) AT TIME ZONE 'America/Fortaleza')::date AS dia,
  (lower(r.periodo) AT TIME ZONE 'America/Fortaleza')::time AS hora_inicio,
  (upper(r.periodo) AT TIME ZONE 'America/Fortaleza')::time AS hora_fim,
  r.id                                                      AS reserva_id,
  u.nome                                                    AS responsavel,
  r.finalidade,
  r.qtd_participantes
FROM reserva r
JOIN sala    s ON s.id = r.sala_id
JOIN usuario u ON u.id = r.usuario_id
WHERE r.status = 'ATIVA';

COMMENT ON VIEW v_agenda_dia IS
  'Agenda diaria de reservas ATIVAS no fuso America/Fortaleza; app filtra por sala_id e dia.';

-- =============================================================================
-- 2. v_reservas_usuario: historico e reservas futuras por usuario
-- =============================================================================
CREATE OR REPLACE VIEW v_reservas_usuario AS
SELECT
  r.usuario_id,
  r.id                           AS reserva_id,
  s.codigo                       AS sala_codigo,
  lower(r.periodo)               AS inicio,
  upper(r.periodo)               AS fim,
  r.status,
  (lower(r.periodo) > now())     AS futura
FROM reserva r
JOIN sala s ON s.id = r.sala_id
ORDER BY lower(r.periodo) DESC, r.id DESC;

COMMENT ON VIEW v_reservas_usuario IS
  'Reservas do usuario ordenadas da mais recente para a mais antiga, com flag futura derivada do tempo.';

-- =============================================================================
-- 3. mv_ocupacao_mensal: ocupacao consolidada de todas as salas por mes
-- =============================================================================
CREATE MATERIALIZED VIEW mv_ocupacao_mensal AS
WITH meses_janela AS (
  SELECT gs::date AS mes
  FROM generate_series(
    date_trunc('month', ((current_date - interval '12 months')::timestamp))::date,
    date_trunc('month', ((current_date + interval '2 months')::timestamp))::date,
    interval '1 month'
  ) AS gs
  UNION
  SELECT DISTINCT
    date_trunc('month', lower(periodo) AT TIME ZONE 'America/Fortaleza')::date AS mes
  FROM reserva
  WHERE status = 'ATIVA'
),
agg_reservas AS (
  SELECT
    r.sala_id,
    date_trunc('month', lower(r.periodo) AT TIME ZONE 'America/Fortaleza')::date AS mes,
    count(*)::bigint AS total_reservas,
    SUM(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0) AS horas_exatas
  FROM reserva r
  WHERE r.status = 'ATIVA'
  GROUP BY r.sala_id, 2
)
SELECT
  s.id     AS sala_id,
  s.codigo AS sala_codigo,
  m.mes,
  COALESCE(a.total_reservas, 0)::bigint AS total_reservas,
  ROUND(COALESCE(a.horas_exatas, 0)::numeric, 2) AS horas_reservadas,
  ROUND(
    (COALESCE(a.horas_exatas, 0) / (((m.mes + interval '1 month')::date - m.mes) * 15.0)) * 100.0,
    2
  ) AS taxa_ocupacao_pct
FROM sala s
CROSS JOIN meses_janela m
LEFT JOIN agg_reservas a
  ON a.sala_id = s.id
 AND a.mes = m.mes
ORDER BY m.mes DESC, s.codigo;

COMMENT ON MATERIALIZED VIEW mv_ocupacao_mensal IS
  'Ocupacao mensal por sala (todas as salas x meses, inclusive 0 reservas). Atualizar com REFRESH MATERIALIZED VIEW CONCURRENTLY (evolucao: pg_cron).';

-- Indice UNIQUE obrigatorio para suportar REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX ux_mv_ocupacao_mensal_sala_mes
  ON mv_ocupacao_mensal (sala_id, mes);

-- =============================================================================
-- 4. v_salas_recursos (opcional de UX): listagem de salas e equipamentos na CLI
-- =============================================================================
CREATE OR REPLACE VIEW v_salas_recursos AS
SELECT
  s.id AS sala_id,
  s.codigo,
  s.nome,
  s.tipo,
  s.capacidade,
  s.ativa,
  COALESCE(
    string_agg(r.nome || ' (' || sr.quantidade || ')', ', ' ORDER BY r.nome),
    'Sem recursos cadastrados'
  ) AS recursos
FROM sala s
LEFT JOIN sala_recurso sr ON sr.sala_id = s.id
LEFT JOIN recurso      r  ON r.id = sr.recurso_id
GROUP BY s.id, s.codigo, s.nome, s.tipo, s.capacidade, s.ativa
ORDER BY s.id;

COMMENT ON VIEW v_salas_recursos IS
  'Apoio de UX para a CLI exibir codigos, capacidades e recursos das salas sem consultar tabelas base.';

RESET ROLE;
