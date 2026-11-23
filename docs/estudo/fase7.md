# Cola de estudo — Fase 7 (Consultas analíticas)

- **`WHERE` vs `HAVING`:** `WHERE` filtra tuplas individuais **antes** da agregação; `HAVING` filtra grupos **depois** do `GROUP BY` (usando agregações como `count(r.id) > 10` ou subconsulta escalar com `AVG`).
- **Window function vs `GROUP BY`:** `GROUP BY` colapsa várias linhas em uma por grupo; *window functions* (`RANK()`, `DENSE_RANK()`, `LAG()`) calculam sobre partições (`OVER (PARTITION BY ...)`) **sem perder** a granularidade de cada linha.
- **`RANK` vs `DENSE_RANK` vs `ROW_NUMBER`:** em empate (`100, 100, 90`), `RANK` pula posições (`1, 1, 3`), `DENSE_RANK` não pula (`1, 1, 2`) e `ROW_NUMBER` numera sem empate (`1, 2, 3`).
- **`CTE` no PostgreSQL 12+:** CTEs não recursivas, sem efeitos colaterais e referenciadas uma vez são *inlined* pelo planner por padrão (podendo usar índices), salvo se marcadas com `AS MATERIALIZED`.
- **`count(*) FILTER (WHERE ...)`:** sintaxe padrão SQL mais limpa e expressiva que `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` para múltiplas contagens condicionais na mesma passagem.
