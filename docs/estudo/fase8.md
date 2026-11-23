# Cola de estudo — Fase 8 (Índices e EXPLAIN ANALYZE)

- **Armadilha do `EXCLUDE`:** o `sem_conflito` cria um índice GiST parcial em `(sala_id, periodo) WHERE status = 'ATIVA'`. Consultas sem `sala_id` ou filtrando por `usuario_id` não o aproveitam, exigindo novos índices.
- **Índice parcial (`WHERE status = 'ATIVA'`) e sobre expressão (`lower(periodo)`):** reduz tamanho em disco e evita indexar linhas canceladas; exige que a consulta use a mesma expressão `lower(periodo)` e `status = 'ATIVA'` para o planner utilizá-lo.
- **B-tree vs GiST:** B-tree atende ordenação e comparações escalares (`=`, `>`, `>=`, `<`) em `usuario_id` e `lower(periodo)`; GiST atende operadores de intervalo (`&&`, `@>`) em `tstzrange`.
- **Ler `EXPLAIN (ANALYZE, BUFFERS)`:** comparar tipo de nó (`Seq Scan` → `Index Scan`/`Index Only Scan`/`Bitmap Index Scan`), `Execution Time`, `Rows Removed by Filter`, `Buffers: shared hit` e `rows` estimadas × reais.
- **Quando o planner ignora um índice e custo:** tabelas pequenas, baixa seletividade (quando retorna grande fração da tabela) ou estatísticas desatualizadas (`ANALYZE`); o custo de ter índices é espaço em disco e escrita mais lenta (`INSERT`/`UPDATE`).
