# Roteiro de Concorrência e Transações — Fase 9

Este roteiro comprova experimentalmente que o PostgreSQL garante a exclusividade de horários (`EXCLUDE USING gist`) e o limite de 3 reservas futuras (`FOR NO KEY UPDATE`) sob acesso simultâneo, operando no nível de isolamento padrão **`READ COMMITTED`**.

---

## 1. Cenário 1 — Mesmo horário em duas sessões simultâneas (≤ 3 minutos)

### Passo a passo para reprodução ao vivo (3 terminais PowerShell)

1. Garanta o banco limpo para a demonstração:
   ```powershell
   docker compose exec -T db sh /projeto/scripts/reset.sh
   ```
2. **Terminal 1 (Sessão A):** conecte ao `psql` e execute a transação sem dar `COMMIT`:
   ```powershell
   docker compose exec db psql -U postgres -d reservas
   ```
   ```sql
   \i /projeto/concorrencia/sessao_A.sql
   ```
3. **Terminal 2 (Sessão B):** em outro terminal, tente reservar um período sobreposto (`15:00–17:00` vs `14:00–16:00`) na mesma sala `5`:
   ```powershell
   docker compose exec db psql -U postgres -d reservas
   ```
   ```sql
   \i /projeto/concorrencia/sessao_B.sql
   ```
   *A Sessão B ficará **travada/bloqueada** aguardando o desfecho da Sessão A.*
4. **Terminal 3 (Sessão C — Observador):** consulte `pg_stat_activity` e `pg_locks` para provar o bloqueio:
   ```powershell
   docker compose exec -T db psql -U postgres -d reservas -c "SELECT pid, state, wait_event_type, wait_event, left(query, 65) AS query FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();" -c "SELECT pid, locktype, mode, granted FROM pg_locks WHERE NOT granted OR locktype = 'transactionid' ORDER BY granted, pid;"
   ```
5. **Desfecho no Terminal 1 (Sessão A):**
   - **Variante 5a (`COMMIT;`):** confirma a reserva de A; imediatamente a Sessão B é desbloqueada e recebe **`RS010`**; finalize B com `ROLLBACK;`.
   - **Variante 5b (`ROLLBACK;`):** desfaz a reserva de A (use outro dia ou rode `reset.sh` antes); imediatamente a Sessão B é desbloqueada e **conclui com sucesso**; finalize B com `COMMIT;`.

### Saída real observada

**Variante 5a (`COMMIT` de A → conflito `RS010` em B):**

```text
[Sessao A pid=2071] criar_reserva retornou id=13035 (SEM COMMIT ainda)
[Sessao C] pg_stat_activity:
  pid=2071 | state=idle in transaction | wait_event_type=Client | wait_event=ClientRead | query=SELECT pg_backend_pid()
  pid=2072 | state=active | wait_event_type=Lock | wait_event=transactionid | query=SELECT criar_reserva($1, $2, $3, $4, $5, $6)
[Sessao C] pg_locks (nao concedidos / transactionid):
  pid=2072 | locktype=transactionid | mode=ShareLock | granted=False
  pid=2071 | locktype=transactionid | mode=ExclusiveLock | granted=True
  pid=2072 | locktype=transactionid | mode=ExclusiveLock | granted=True
[Sessao A] executou COMMIT
[Sessao B] desfecho -> ERRO SQLSTATE=RS010: Conflito de horario: a sala 5 ja esta reservada em parte do periodo pedido.
```

**Variante 5b (`ROLLBACK` de A → sucesso em B):**

```text
[Sessao A pid=2074] criar_reserva retornou id=13037 (SEM COMMIT ainda)
[Sessao C] pg_stat_activity:
  pid=2074 | state=idle in transaction | wait_event_type=Client | wait_event=ClientRead | query=SELECT pg_backend_pid()
  pid=2075 | state=active | wait_event_type=Lock | wait_event=transactionid | query=SELECT criar_reserva($1, $2, $3, $4, $5, $6)
[Sessao C] pg_locks (nao concedidos / transactionid):
  pid=2075 | locktype=transactionid | mode=ShareLock | granted=False
  pid=2074 | locktype=transactionid | mode=ExclusiveLock | granted=True
  pid=2075 | locktype=transactionid | mode=ExclusiveLock | granted=True
[Sessao A] executou ROLLBACK
[Sessao B] desfecho -> SUCESSO: id=13038 confirmado (COMMIT)
```

**Por que a Sessão B espera?** Ao inserir na tabela `reserva`, o índice GiST da constraint `sem_conflito` encontra a entrada inserida pela Sessão A cujo `xmax`/`xmin` ainda pertence a uma transação aberta. Como o PostgreSQL ainda não sabe se A vai confirmar ou desfazer, B solicita `ShareLock` no `transactionid` da Sessão A (`wait_event_type = Lock`, `wait_event = transactionid`) e aguarda.

---

## 2. Cenário 2 — Corrida no limite de 3 reservas futuras (*Write Skew*)

Neste experimento, um usuário que já possui **2 reservas futuras ativas** recebe duas requisições simultâneas para salas distintas (`sala 1` e `sala 2`, portanto sem conflito no `EXCLUDE`).

### Com `FOR NO KEY UPDATE` na linha de `usuario` (`sql/03_triggers.sql` ativo)

```text
Usuario 3 (2 previas) -> ['Sessao A: SUCESSO id=13041', 'Sessao B: ERRO RS008 - Limite atingido: o usuario ja possui 3 reservas futuras ativas (maximo 3).'] | Total futuras = 3
```

### Sem `FOR NO KEY UPDATE` (demonstração didática comentando o lock)

Removendo temporariamente o `PERFORM 1 FROM usuario WHERE id = NEW.usuario_id FOR NO KEY UPDATE;` em `fn_regras_reserva()` e disparando as duas sessões em barreira simultânea, ambas executam o `SELECT count(*)` no mesmo snapshot de `READ COMMITTED`, leem `2` reservas e ambas passam:

```text
Tentativa 1 usuario 22 -> ['Sessao A: SUCESSO id=13046', 'Sessao B: SUCESSO id=13045'] | Total futuras = 4
```

*Logo após a demonstração, o banco foi restaurado via `scripts/reset.sh` com o `FOR NO KEY UPDATE` ativo em `sql/03_triggers.sql`.*

**Por que `FOR NO KEY UPDATE` e não `FOR UPDATE`?** `FOR UPDATE` conflitaria com os locks `FOR KEY SHARE` que o próprio PostgreSQL adquire na verificação de integridade referencial das chaves estrangeiras (`reserva.usuario_id → usuario.id`). `FOR NO KEY UPDATE` serializa transações concorrentes sobre o mesmo usuário sem bloquear checagens de FK.

---

## 3. Cenário 3 — Teste automatizado (`concorrencia/teste_concorrencia.py`)

O script sincroniza **20 threads** com conexões independentes via `threading.Barrier` em **10 baterias** para o mesmo slot da sala `5`, além de validar a corrida do limite de 3 reservas com **10 threads** no mesmo usuário:

```text
=== Cenario 3: 10 baterias x 20 threads (role=postgres) ===
  Bateria 01/10 OK: 1 sucesso (reserva_id=13014), 19 RS010, sobrepostas no banco=1
  Bateria 02/10 OK: 1 sucesso (reserva_id=13034), 19 RS010, sobrepostas no banco=1
  Bateria 03/10 OK: 1 sucesso (reserva_id=13054), 19 RS010, sobrepostas no banco=1
  Bateria 04/10 OK: 1 sucesso (reserva_id=13075), 19 RS010, sobrepostas no banco=1
  Bateria 05/10 OK: 1 sucesso (reserva_id=13096), 19 RS010, sobrepostas no banco=1
  Bateria 06/10 OK: 1 sucesso (reserva_id=13114), 19 RS010, sobrepostas no banco=1
  Bateria 07/10 OK: 1 sucesso (reserva_id=13135), 19 RS010, sobrepostas no banco=1
  Bateria 08/10 OK: 1 sucesso (reserva_id=13156), 19 RS010, sobrepostas no banco=1
  Bateria 09/10 OK: 1 sucesso (reserva_id=13176), 19 RS010, sobrepostas no banco=1
  Bateria 10/10 OK: 1 sucesso (reserva_id=13194), 19 RS010, sobrepostas no banco=1
=== Cenario 2 (automatizado): corrida no limite de 3 reservas futuras ===
  Corrida limite OK: usuario 2 -> 1 sucesso, 9 RS008, total futuras=3
TODOS OS TESTES DE CONCORRENCIA PASSARAM.
```

*(Nota: após a Fase 10, `teste_concorrencia.py` detecta automaticamente a role `app_reservas` e passa a executar todas as threads usando a role restrita da aplicação).*

---

## 4. Conclusão

1. **Zero reservas sobrepostas** mesmo sob 20 requisições simultâneas idênticas em 10 rodadas seguidas (`sem_conflito` + `RS010`).
2. **Zero violações do limite de 3 reservas futuras** mesmo sob 10 requisições paralelas para o mesmo usuário em salas distintas (`FOR NO KEY UPDATE` + `RS008`).
3. Não foi necessário elevar o nível de isolamento para `SERIALIZABLE`: o PostgreSQL resolveu todas as corridas de forma determinística no padrão `READ COMMITTED`.
