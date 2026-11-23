# Cola de estudo — Fase 6 (Carga massiva)

- **`generate_series` + `CROSS JOIN LATERAL`:** `generate_series` gera os 365 dias passados e `CROSS JOIN LATERAL` calcula o `timestamptz` inicial local (`AT TIME ZONE 'America/Fortaleza'`) uma única vez por linha candidata, reusando `t.ini` no `tstzrange` e no `criada_em`.
- **`AS MATERIALIZED` na CTE:** desde o PostgreSQL 12, CTEs simples são *inlined*; `AS MATERIALIZED` impede o otimizador de reavaliar `random()` múltiplas vezes ou misturar os valores sorteados.
- **Estratégia conflito-free por construção:** os slots (`07, 09, 11, 13, 15, 17, 19` h com duração ≤ 120 min) são disjuntos por `(sala, dia)`. Assim o `EXCLUDE` e os triggers ficam **ligados** durante a carga como prova real de conformidade.
- **Passado não conta como futuro:** o limite de 3 reservas ativas verifica `lower(periodo) > now()`; reservas históricas não bloqueiam os usuários, e nas futuras usamos `row_number() % n_usuarios` (excluindo IDs de demo).
- **`UPDATE` para `CANCELADA`:** simula ~8% de cancelamentos e popula `log_reserva` com eventos `CANCELAMENTO` via `trg_audit_reserva`.
