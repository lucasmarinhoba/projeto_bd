# Consultas Analíticas — Sistema de Reserva de Salas e Laboratórios

Execução medida em **PostgreSQL 16** com `\timing on` sobre o volume completo da Fase 6 (`13.013` reservas, sendo `11.984 ATIVA` e `1.029 CANCELADA`). Todas as consultas executaram muito abaixo do teto de **2.000 ms**.

| # | Técnicas principais | Linhas | Tempo real (`psql`) |
|---|---|---|---|
| **Q1** | `JOIN` + `GROUP BY` + `HAVING` | 15 (top 15) | `281.288 ms` |
| **Q2** | `JOIN` + `GROUP BY` + subconsulta escalar no `HAVING` | 9 | `76.602 ms` |
| **Q3** | `CTE` + `count(*) FILTER (WHERE ...)` | 21 | `88.870 ms` |
| **Q4** | `CTE` + `RANK() OVER (...)` + `LAG() OVER (...)` | 20 | `58.151 ms` |
| **Q5** | `CTE` + `JOIN` + `DENSE_RANK() OVER (...)` | 6 | `32.799 ms` |

---

## Q1 — Usuários mais frequentes nos últimos 90 dias

1. **Pergunta de negócio:** Quais usuários têm **mais de 10** reservas ativas nos últimos 90 dias e quantas horas somam?

2. **SQL comentado:**

```sql
-- JOIN entre usuario e reserva, filtrando reservas ATIVAS nos ultimos 90 dias antes do agrupamento
-- e usando HAVING para manter apenas usuarios com mais de 10 reservas no periodo.
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
```

3. **Saída real (`psql`, Time: `281.288 ms`):**

```text
 usuario_id | matricula |               nome               |   tipo    | total_reservas_90d | horas_reservadas_90d 
------------+-----------+----------------------------------+-----------+--------------------+----------------------
        146 | PROF0025  | Prof. Bruno Araujo Nascimento    | PROFESSOR |                 32 |                48.00
         91 | 20260089  | Thiago Souza Rodrigues           | ALUNO     |                 29 |                43.00
        116 | 20260114  | Vitoria Silva Almeida            | ALUNO     |                 28 |                42.50
         87 | 20260085  | Gabriela Martins Carvalho        | ALUNO     |                 28 |                42.00
         41 | 20260039  | Arthur Gomes Alves               | ALUNO     |                 29 |                41.50
         54 | 20260052  | Arthur Nascimento Ribeiro        | ALUNO     |                 27 |                41.50
         51 | 20260049  | Daniel Silva Lima                | ALUNO     |                 27 |                41.00
         59 | 20260057  | Sofia Ribeiro Pereira            | ALUNO     |                 27 |                41.00
         14 | 20260012  | Henrique Nascimento Fernandes    | ALUNO     |                 26 |                40.50
         50 | 20260048  | Vitoria Lima Martins             | ALUNO     |                 29 |                40.00
         13 | 20260011  | Mariana Rocha Ribeiro            | ALUNO     |                 27 |                40.00
        123 | PROF0002  | Prof. Isabela Ribeiro Nascimento | PROFESSOR |                 25 |                39.50
         96 | 20260094  | Mariana Lima Nascimento          | ALUNO     |                 25 |                38.50
         85 | 20260083  | Larissa Souza Nascimento         | ALUNO     |                 24 |                38.50
        118 | 20260116  | Ana Araujo Almeida               | ALUNO     |                 27 |                37.50
(15 rows)
```

4. **Interpretação:** Os usuários no topo da utilização trimestral acumularam entre `24` e `32` reservas ativas (`37.50` a `48.00` horas), com média de ~1,5 hora por reserva (coerente com as durações sorteadas de 60, 90 e 120 minutos).
5. **Técnicas usadas e por quê:** `WHERE` filtra o recorte temporal e `status = 'ATIVA'` antes da agregação; `GROUP BY` agrega por usuário; `HAVING count(r.id) > 10` filtra grupos já agregados (o que não é possível no `WHERE`).

---

## Q2 — Salas acima da média mensal de ocupação

1. **Pergunta de negócio:** Quais salas tiveram, no último mês fechado (`2026-10`), taxa de ocupação **acima da média** de todas as salas?

2. **SQL comentado:**

```sql
-- Compara as horas reservadas de cada sala no ultimo mes fechado com a media global
-- de todas as 20 salas (incluindo salas com 0 reserva via LEFT JOIN na subconsulta escalar).
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
```

3. **Saída real (`psql`, Time: `76.602 ms`):**

```text
 sala_id | codigo |    tipo     | total_reservas | horas_reservadas | taxa_ocupacao_pct 
---------+--------+-------------+----------------+------------------+-------------------
      14 | LAB-02 | LABORATORIO |             59 |            91.50 |             19.68
      20 | LAB-08 | LABORATORIO |             61 |            90.00 |             19.35
       4 | A-104  | SALA        |             54 |            85.00 |             18.28
      18 | LAB-06 | LABORATORIO |             57 |            85.00 |             18.28
      16 | LAB-04 | LABORATORIO |             56 |            83.00 |             17.85
      13 | LAB-01 | LABORATORIO |             56 |            82.50 |             17.74
      11 | B-203  | SALA        |             51 |            77.50 |             16.67
       9 | B-201  | SALA        |             51 |            77.00 |             16.56
      15 | LAB-03 | LABORATORIO |             54 |            76.50 |             16.45
(9 rows)
```

4. **Interpretação:** Das `20` salas cadastradas, `9` ficaram acima da média de ocupação em outubro (`2026-10`), lideradas por `LAB-02` (`91.50 h` / `19.68%`) e `LAB-08` (`90.00 h` / `19.35%`). Os valores de horas e taxas coincidem exatamente com `mv_ocupacao_mensal`.
5. **Técnicas usadas e por quê:** `JOIN` + `GROUP BY` + **subconsulta escalar no `HAVING`**. Como o denominador de horas disponíveis (`31 dias × 15 h = 465 h`) é constante para todas as salas no mesmo mês, comparar horas no `HAVING` equivale exatamente a comparar `taxa_ocupacao_pct`, preservando o uso de `LEFT JOIN` na subconsulta para considerar todas as salas.

---

## Q3 — Distribuição semanal × faixa horária e taxa de cancelamento

1. **Pergunta de negócio:** Como as reservas se distribuem por dia da semana e faixa horária e qual o **% de cancelamento** em cada célula?

2. **SQL comentado:**

```sql
-- CTE classifica cada reserva no fuso local (America/Fortaleza) por dia ISO e turno;
-- a consulta externa usa COUNT(*) FILTER (WHERE ...) para contar ativas e canceladas em uma unica varredura.
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
```

3. **Saída real (`psql`, Time: `88.870 ms`):**

```text
 dia_semana |  faixa_horaria   | total_reservas | ativas | canceladas | pct_cancelamento 
------------+------------------+----------------+--------+------------+------------------
 1-Segunda  | 1-Manha (07-12h) |            789 |    733 |         56 |             7.10
 1-Segunda  | 2-Tarde (12-18h) |            806 |    739 |         67 |             8.31
 1-Segunda  | 3-Noite (18-22h) |            269 |    242 |         27 |            10.04
 2-Terca    | 1-Manha (07-12h) |            790 |    728 |         62 |             7.85
 2-Terca    | 2-Tarde (12-18h) |            837 |    783 |         54 |             6.45
 2-Terca    | 3-Noite (18-22h) |            262 |    239 |         23 |             8.78
 3-Quarta   | 1-Manha (07-12h) |            789 |    718 |         71 |             9.00
 3-Quarta   | 2-Tarde (12-18h) |            820 |    754 |         66 |             8.05
 3-Quarta   | 3-Noite (18-22h) |            266 |    245 |         21 |             7.89
 4-Quinta   | 1-Manha (07-12h) |            807 |    744 |         63 |             7.81
 4-Quinta   | 2-Tarde (12-18h) |            804 |    732 |         72 |             8.96
 4-Quinta   | 3-Noite (18-22h) |            272 |    251 |         21 |             7.72
 5-Sexta    | 1-Manha (07-12h) |            766 |    689 |         77 |            10.05
 5-Sexta    | 2-Tarde (12-18h) |            771 |    712 |         59 |             7.65
 5-Sexta    | 3-Noite (18-22h) |            261 |    242 |         19 |             7.28
 6-Sabado   | 1-Manha (07-12h) |            797 |    730 |         67 |             8.41
 6-Sabado   | 2-Tarde (12-18h) |            767 |    710 |         57 |             7.43
 6-Sabado   | 3-Noite (18-22h) |            259 |    241 |         18 |             6.95
 7-Domingo  | 1-Manha (07-12h) |            779 |    731 |         48 |             6.16
 7-Domingo  | 2-Tarde (12-18h) |            834 |    773 |         61 |             7.31
 7-Domingo  | 3-Noite (18-22h) |            268 |    248 |         20 |             7.46
(21 rows)
```

4. **Interpretação:** Manhã (`07, 09, 11h`) e Tarde (`13, 15, 17h`) concentram ~3× mais reservas que a Noite (`19h`) porque possuem 3 slots por dia contra 1 slot noturno. A taxa de cancelamento varia entre `6.16%` (Domingo Manhã) e `10.05%` (Sexta Manhã), centrada em torno dos ~8% simulados no seed.
5. **Técnicas usadas e por quê:** `CTE` melhora a legibilidade evitando repetir expressões de `EXTRACT(... AT TIME ZONE ...)` no `GROUP BY`; `count(*) FILTER (WHERE ...)` substitui `SUM(CASE ...)` de forma idiomática no PostgreSQL.

---

## Q4 — Ranking mensal das salas e variação em relação ao mês anterior

1. **Pergunta de negócio:** Qual o **ranking mensal** das salas por horas reservadas no último mês fechado e qual foi a variação em relação ao mês anterior?

2. **SQL comentado:**

```sql
-- Calcula as horas por (sala, mes) nos ultimos 3 meses fechados para que LAG() enxergue o mes anterior,
-- aplica RANK() e LAG() na segunda CTE e filtra o ultimo mes fechado apenas no SELECT final.
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
```

3. **Saída real (`psql`, Time: `58.151 ms`):**

```text
    mes     | ranking_mes | sala_codigo | horas_reservadas | horas_mes_anterior | variacao_horas | variacao_pct 
------------+-------------+-------------+------------------+--------------------+----------------+--------------
 2026-10-01 |           1 | LAB-02      |            91.50 |              69.00 |          22.50 |        32.61
 2026-10-01 |           2 | LAB-08      |            90.00 |              66.00 |          24.00 |        36.36
 2026-10-01 |           3 | A-104       |            85.00 |              78.50 |           6.50 |         8.28
 2026-10-01 |           3 | LAB-06      |            85.00 |              62.50 |          22.50 |        36.00
 2026-10-01 |           5 | LAB-04      |            83.00 |              57.50 |          25.50 |        44.35
 2026-10-01 |           6 | LAB-01      |            82.50 |              72.00 |          10.50 |        14.58
 2026-10-01 |           7 | B-203       |            77.50 |              64.00 |          13.50 |        21.09
 2026-10-01 |           8 | B-201       |            77.00 |              74.50 |           2.50 |         3.36
 2026-10-01 |           9 | LAB-03      |            76.50 |              70.50 |           6.00 |         8.51
 2026-10-01 |          10 | A-105       |            74.50 |              64.50 |          10.00 |        15.50
 2026-10-01 |          10 | B-204       |            74.50 |              68.50 |           6.00 |         8.76
 2026-10-01 |          12 | A-107       |            74.00 |              74.00 |           0.00 |         0.00
 2026-10-01 |          13 | A-102       |            72.00 |              92.00 |         -20.00 |       -21.74
 2026-10-01 |          14 | A-103       |            71.50 |              73.00 |          -1.50 |        -2.05
 2026-10-01 |          15 | LAB-05      |            71.00 |              85.00 |         -14.00 |       -16.47
 2026-10-01 |          16 | LAB-07      |            68.00 |              84.00 |         -16.00 |       -19.05
 2026-10-01 |          17 | B-202       |            66.50 |              75.00 |          -8.50 |       -11.33
 2026-10-01 |          18 | A-108       |            64.00 |              58.00 |           6.00 |        10.34
 2026-10-01 |          19 | A-101       |            62.50 |              88.00 |         -25.50 |       -28.98
 2026-10-01 |          20 | A-106       |            49.50 |              89.00 |         -39.50 |       -44.38
(20 rows)
```

4. **Interpretação:** Observam-se dois empates reais no mês `2026-10-01`: `A-104` e `LAB-06` empatam em `3º` (`85.00 h`, pulando o 4º para `5º`) e `A-105` e `B-204` empatam em `10º` (`74.50 h`, pulando para `12º`). Todas as horas das primeiras 10 salas batem 100% com `mv_ocupacao_mensal` (`91.50`, `90.00`, `85.00`, `85.00`, `83.00`, `82.50`, `77.50`, `77.00`, `76.50`, `74.50`).
5. **Técnicas usadas e por quê:** `RANK() OVER (PARTITION BY mes ...)` preserva o salto ordinal de empates; `LAG() OVER (PARTITION BY sala_id ORDER BY mes)` acessa a linha do mês anterior sem precisar de auto-junção (`self-join`); o filtro final do mês fica fora da CTE `com_janela` para não ocultar setembro do `LAG()`.

---

## Q5 — Top 3 usuários por categoria (ALUNO / PROFESSOR)

1. **Pergunta de negócio:** Quais os **Top 3 usuários** de cada tipo (`ALUNO` e `PROFESSOR`) por volume total de horas reservadas?

2. **SQL comentado:**

```sql
-- Agrega reservas ATIVAS por usuario e aplica DENSE_RANK() particionado por tipo
-- para retornar o podio (posicao <= 3) de alunos e professores sem saltar posicoes em empates.
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
```

3. **Saída real (`psql`, Time: `32.799 ms`):**

```text
   tipo    | posicao | usuario_id | matricula |               nome               | total_reservas | horas_reservadas 
-----------+---------+------------+-----------+----------------------------------+----------------+------------------
 ALUNO     |       1 |         54 | 20260052  | Arthur Nascimento Ribeiro        |            104 |           160.00
 ALUNO     |       2 |        121 | 20260119  | Larissa Alves Pereira            |             97 |           155.00
 ALUNO     |       3 |         51 | 20260049  | Daniel Silva Lima                |             98 |           152.00
 PROFESSOR |       1 |        141 | PROF0020  | Prof. Daniel Gomes Lima          |            106 |           164.00
 PROFESSOR |       2 |        146 | PROF0025  | Prof. Bruno Araujo Nascimento    |             99 |           151.50
 PROFESSOR |       3 |        123 | PROF0002  | Prof. Isabela Ribeiro Nascimento |             98 |           149.50
(6 rows)
```

4. **Interpretação:** Entre alunos e professores, os usuários mais ativos acumulam entre `97` e `106` reservas ao longo do ano (`149.50` a `164.00` horas). O critério de ordenação prioriza `horas_reservadas` e desempata por `total_reservas`.
5. **Técnicas usadas e por quê:** `CTE` + `JOIN` + `DENSE_RANK() OVER (PARTITION BY tipo ...)`. `DENSE_RANK()` garante que, havendo empate no 1º ou 2º lugar, a próxima posição distinta não seja pulada (ao contrário de `RANK()`), e o filtro `WHERE posicao <= 3` é feito fora da CTE porque *window functions* não podem aparecer diretamente em `WHERE`.
