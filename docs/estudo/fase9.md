# Cola de estudo — Fase 9 (Concorrência e transações)

- **`READ COMMITTED` e snapshot por comando:** no nível padrão do PostgreSQL, cada instrução enxerga os dados já confirmados antes de ela iniciar (e reavalia após aguardar um lock).
- **Por que o `EXCLUDE` funciona em qualquer nível:** mesmo em `READ COMMITTED`, o índice GiST de `sem_conflito` detecta a tupla conflitante não confirmada e bloqueia a 2ª sessão (`wait_event_type = Lock`, `wait_event = transactionid`) até o `COMMIT`/`ROLLBACK` da 1ª.
- **`FOR NO KEY UPDATE` vs `FOR UPDATE`:** trava a linha do `usuario` para serializar a contagem de até 3 reservas futuras (evitando *write skew*), sem bloquear `FOR KEY SHARE` das verificações de chave estrangeira.
- **MVCC (Multi-Version Concurrency Control):** leitores nunca bloqueiam escritores e escritores nunca bloqueiam leitores (`SELECT` enxerga o snapshot consistente).
- **`40P01` e `40001`:** `40P01` é *deadlock* (travamento mútuo detectado após `deadlock_timeout = 1s`); `40001` é falha de serialização (`SERIALIZABLE`/`REPEATABLE READ`). Travar sempre na mesma ordem (`usuario → reserva`) evita deadlocks.
