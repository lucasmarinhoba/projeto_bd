-- analise/consultas_analiticas.sql
-- Cinco consultas analiticas cobrindo JOIN, GROUP BY/HAVING, subconsulta escalar,
-- CTE, FILTER e funcoes de janela (RANK, DENSE_RANK, LAG).

SET search_path = reservas, public;
SET timezone = 'America/Fortaleza';

-- =============================================================================
-- Q1: Usuarios com mais de 10 reservas ativas nos ultimos 90 dias e soma de horas
-- Tecnicas: JOIN + GROUP BY + HAVING
-- =============================================================================
SELECT
  u.id AS usuario_id,
  u.matricula,
  u.nome,
  u.tipo,
  count(r.id) AS total_reservas_90d,
  ROUND(SUM(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0), 2) AS horas_reservadas_90d
FROM usuario u
JOIN reserva r ON r.usuario_id = u.id
WHERE r.status = 'ATIVA'
  AND lower(r.periodo) >= now() - interval '90 days'
  AND lower(r.periodo) <= now()
GROUP BY u.id, u.matricula, u.nome, u.tipo
HAVING count(r.id) > 10
ORDER BY horas_reservadas_90d DESC, total_reservas_90d DESC, u.id
LIMIT 15;

-- =============================================================================
-- Q2: Salas com taxa de ocupacao acima da media no ultimo mes fechado
-- Tecnicas: JOIN + GROUP BY + subconsulta escalar no HAVING
-- =============================================================================
SELECT
  s.id AS sala_id,
  s.codigo,
  s.tipo,
  count(r.id) AS total_reservas,
  ROUND(SUM(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0), 2) AS horas_reservadas,
  ROUND(
    (SUM(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0)
     / (((date_trunc('month', (current_date - interval '1 month')::timestamp)::date + interval '1 month')::date
         - date_trunc('month', (current_date - interval '1 month')::timestamp)::date) * 15.0)) * 100.0,
    2
  ) AS taxa_ocupacao_pct
FROM sala s
JOIN reserva r ON r.sala_id = s.id
WHERE r.status = 'ATIVA'
  AND lower(r.periodo) >= (date_trunc('month', (current_date - interval '1 month')::timestamp)::date::timestamp AT TIME ZONE 'America/Fortaleza')
  AND lower(r.periodo) <  ((date_trunc('month', (current_date - interval '1 month')::timestamp)::date + interval '1 month')::date::timestamp AT TIME ZONE 'America/Fortaleza')
GROUP BY s.id, s.codigo, s.tipo
HAVING SUM(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0) > (
  SELECT AVG(horas_sala)
  FROM (
    SELECT
      s2.id,
      COALESCE(SUM(EXTRACT(EPOCH FROM (upper(r2.periodo) - lower(r2.periodo))) / 3600.0), 0) AS horas_sala
    FROM sala s2
    LEFT JOIN reserva r2
      ON r2.sala_id = s2.id
     AND r2.status = 'ATIVA'
     AND lower(r2.periodo) >= (date_trunc('month', (current_date - interval '1 month')::timestamp)::date::timestamp AT TIME ZONE 'America/Fortaleza')
     AND lower(r2.periodo) <  ((date_trunc('month', (current_date - interval '1 month')::timestamp)::date + interval '1 month')::date::timestamp AT TIME ZONE 'America/Fortaleza')
    GROUP BY s2.id
  ) AS medias_salas
)
ORDER BY taxa_ocupacao_pct DESC, s.codigo;

-- =============================================================================
-- Q3: Distribuicao de reservas por dia da semana x faixa horaria e % cancelamento
-- Tecnicas: CTE + count(*) FILTER (WHERE ...)
-- =============================================================================
WITH reservas_classificadas AS (
  SELECT
    EXTRACT(ISODOW FROM (lower(periodo) AT TIME ZONE 'America/Fortaleza'))::int AS dia_num,
    CASE EXTRACT(ISODOW FROM (lower(periodo) AT TIME ZONE 'America/Fortaleza'))::int
      WHEN 1 THEN '1-Segunda'
      WHEN 2 THEN '2-Terca'
      WHEN 3 THEN '3-Quarta'
      WHEN 4 THEN '4-Quinta'
      WHEN 5 THEN '5-Sexta'
      WHEN 6 THEN '6-Sabado'
      WHEN 7 THEN '7-Domingo'
    END AS dia_semana,
    CASE
      WHEN EXTRACT(HOUR FROM (lower(periodo) AT TIME ZONE 'America/Fortaleza')) < 12 THEN '1-Manha (07-12h)'
      WHEN EXTRACT(HOUR FROM (lower(periodo) AT TIME ZONE 'America/Fortaleza')) < 18 THEN '2-Tarde (12-18h)'
      ELSE '3-Noite (18-22h)'
    END AS faixa_horaria,
    status
  FROM reserva
)
SELECT
  dia_semana,
  faixa_horaria,
  count(*) AS total_reservas,
  count(*) FILTER (WHERE status = 'ATIVA') AS ativas,
  count(*) FILTER (WHERE status = 'CANCELADA') AS canceladas,
  ROUND(100.0 * count(*) FILTER (WHERE status = 'CANCELADA') / count(*), 2) AS pct_cancelamento
FROM reservas_classificadas
GROUP BY dia_num, dia_semana, faixa_horaria
ORDER BY dia_num, faixa_horaria;

-- =============================================================================
-- Q4: Ranking mensal das salas por horas reservadas e variacao vs mes anterior
-- Tecnicas: CTE + Window functions RANK() OVER e LAG() OVER
-- =============================================================================
WITH horas_mensais AS (
  SELECT
    s.id AS sala_id,
    s.codigo AS sala_codigo,
    date_trunc('month', lower(r.periodo) AT TIME ZONE 'America/Fortaleza')::date AS mes,
    ROUND(SUM(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0), 2) AS horas_reservadas
  FROM sala s
  JOIN reserva r ON r.sala_id = s.id
  WHERE r.status = 'ATIVA'
    AND date_trunc('month', lower(r.periodo) AT TIME ZONE 'America/Fortaleza')::date
        BETWEEN date_trunc('month', (current_date - interval '3 months')::timestamp)::date
            AND date_trunc('month', (current_date - interval '1 month')::timestamp)::date
  GROUP BY s.id, s.codigo, 3
),
com_janela AS (
  SELECT
    sala_id,
    sala_codigo,
    mes,
    horas_reservadas,
    RANK() OVER (PARTITION BY mes ORDER BY horas_reservadas DESC) AS ranking_mes,
    LAG(horas_reservadas) OVER (PARTITION BY sala_id ORDER BY mes) AS horas_mes_anterior
  FROM horas_mensais
)
SELECT
  mes,
  ranking_mes,
  sala_codigo,
  horas_reservadas,
  horas_mes_anterior,
  ROUND(horas_reservadas - horas_mes_anterior, 2) AS variacao_horas,
  ROUND(((horas_reservadas - horas_mes_anterior) / NULLIF(horas_mes_anterior, 0)) * 100.0, 2) AS variacao_pct
FROM com_janela
WHERE mes = date_trunc('month', (current_date - interval '1 month')::timestamp)::date
ORDER BY ranking_mes, sala_codigo;

-- =============================================================================
-- Q5: Top 3 usuarios de cada tipo (ALUNO / PROFESSOR) por horas reservadas
-- Tecnicas: CTE + JOIN + Window function DENSE_RANK() OVER (PARTITION BY tipo ...)
-- =============================================================================
WITH resumo_usuario AS (
  SELECT
    u.id AS usuario_id,
    u.matricula,
    u.nome,
    u.tipo,
    count(r.id) AS total_reservas,
    ROUND(SUM(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0), 2) AS horas_reservadas
  FROM usuario u
  JOIN reserva r ON r.usuario_id = u.id
  WHERE r.status = 'ATIVA'
    AND u.tipo IN ('ALUNO', 'PROFESSOR')
  GROUP BY u.id, u.matricula, u.nome, u.tipo
),
ranqueados AS (
  SELECT
    *,
    DENSE_RANK() OVER (PARTITION BY tipo ORDER BY horas_reservadas DESC, total_reservas DESC) AS posicao
  FROM resumo_usuario
)
SELECT
  tipo,
  posicao,
  usuario_id,
  matricula,
  nome,
  total_reservas,
  horas_reservadas
FROM ranqueados
WHERE posicao <= 3
ORDER BY tipo, posicao, usuario_id;
