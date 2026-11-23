# Cola de estudo — Fase 5 (Views e Materialized View)

- **View vs Materialized View:** uma **view** é uma consulta salva executada a cada leitura (sempre atual); uma **materialized view** persiste o resultado em disco (leitura instantânea, mas fica defasada até um `REFRESH`).
- **Por que agenda é view e ocupação é matview:** a agenda diária precisa refletir reservas recém-criadas na hora; o relatório mensal agrega milhares de linhas e tolera atualização periódica (`REFRESH` ou `pg_cron`).
- **Por que `CONCURRENTLY` exige índice `UNIQUE`:** o PostgreSQL usa a chave única (`sala_id, mes`) para comparar o estado antigo com o novo e aplicar o delta sem bloquear leituras simultâneas.
- **Privilégio do dono (`reservas_owner`):** por padrão (`security_invoker` desligado), views leem as tabelas com os privilégios do dono, permitindo que `app_reservas` consulte as views sem ter `SELECT` nas tabelas base.
- **Regra de mesmo dia local:** garante que toda reserva pertence a um único mês em `America/Fortaleza`, alinhando `mv_ocupacao_mensal` 100% com `taxa_ocupacao(sala, mes)`.
