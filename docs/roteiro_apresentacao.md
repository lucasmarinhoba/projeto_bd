# Roteiro da Apresentação e Guia do Ensaio Oral

Este documento organiza a apresentação prática de **20 minutos** entre **Aluno A** e **Aluno B** (fiel ao esquema da seção 5 do plano) e o protocolo de **ensaio oral cruzado**.

> **Regra da avaliação oral:** a arguição é **individual** — o professor pode perguntar qualquer assunto a qualquer integrante. Os papéis A/B dividem apenas a condução das telas durante a apresentação.

---

## 1. Preparação 2 minutos antes de apresentar

```powershell
# 1) Garantir banco 100% limpo e populado com IDs demo livres no futuro
docker compose exec -T db sh /projeto/scripts/reset.sh

# 2) Garantir que os testes passam antes de começar
docker compose exec -T db sh /projeto/scripts/test.sh

# 3) Deixar abertos:
# - Janela 1: código/docs no editor (docs/DER_conceitual.png, sql/02_tabelas.sql, sql/03_triggers.sql, analise/explain/)
# - Janela 2 (Terminal A): psql como postgres -> docker compose exec db psql -U postgres -d reservas
# - Janela 3 (Terminal B): psql livre para Sessão B (concorrência) ou app_reservas
# - Janela 4 (Terminal C): PowerShell na raiz do projeto (CLI / Página Web / consultas observadoras)
```

---

## 2. Cronograma Minuto a Minuto (20 min)

### 0–2 min · Arquitetura, DER e 3FN (**Aluno A**)
- Explicar a tese do projeto: **casca fina em Python + toda inteligência no PostgreSQL 16** (zero ORM, zero validação de regra no código da app).
- Mostrar [`docs/DER_conceitual.png`](DER_conceitual.png) e [`docs/modelagem_3fn.md`](modelagem_3fn.md): as 6 tabelas (`usuario`, `sala`, `recurso`, `sala_recurso`, `reserva`, `log_reserva`), `ON DELETE RESTRICT` vs `CASCADE`, `CONCLUIDA` omitido por derivar do tempo, e `log_reserva.jsonb` como desnormalização intencional *append-only*.

### 2–5 min · DDL, Tipos e Integridade Declarativa (`EXCLUDE`) (**Aluno A**)
- Mostrar no `psql` ou em `sql/01_tipos.sql` / `sql/02_tabelas.sql`: os 3 ENUMs, 2 DOMAINs (`email_t`, `qtd_positiva`), `ck_periodo_valido` (`[)`), `ck_cancelamento_coerente` e `sem_conflito` (`EXCLUDE USING gist`).
- Demonstrar violação ao vivo direto na tabela (com `ROLLBACK` ao final para não deixar lixo):

```sql
BEGIN;
INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes)
VALUES (1, 5, tstzrange((current_date + 20 + time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza',
                       (current_date + 20 + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza', '[)'), 10);

-- Adjacente (10:00-12:00) PASSA por causa do intervalo [):
INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes)
VALUES (2, 5, tstzrange((current_date + 20 + time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza',
                       (current_date + 20 + time '12:00')::timestamp AT TIME ZONE 'America/Fortaleza', '[)'), 10);

-- Sobreposta (09:00-11:00) FALHA com 23P01 direto no banco:
INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes)
VALUES (2, 5, tstzrange((current_date + 20 + time '09:00')::timestamp AT TIME ZONE 'America/Fortaleza',
                       (current_date + 20 + time '11:00')::timestamp AT TIME ZONE 'America/Fortaleza', '[)'), 10);
ROLLBACK;
```

### 5–8 min · Triggers, Functions e Auditoria (**Aluno B**)
- Explicar por que `trg_regras_reserva` é `BEFORE` e `trg_audit_reserva` é `AFTER` (`RETURN NEW` vs `RETURN NULL`, `SECURITY DEFINER`, `SET search_path`).
- Provocar 3 erros diferentes via `criar_reserva(...)` direto no `psql` (`RS005` duração, `RS006` horário/virada, `RS007` capacidade):

```sql
-- 1) Duracao invalida (< 30 min -> RS005)
SELECT criar_reserva(1, 5, (current_date+20+time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza',
                           (current_date+20+time '08:15')::timestamp AT TIME ZONE 'America/Fortaleza', 10, 'Curta');

-- 2) Fora do horario 07h-22h -> RS006
SELECT criar_reserva(1, 5, (current_date+20+time '06:00')::timestamp AT TIME ZONE 'America/Fortaleza',
                           (current_date+20+time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza', 10, 'Cedo');

-- 3) Capacidade excedida (sala 5 comporta 40 -> RS007)
SELECT criar_reserva(1, 5, (current_date+20+time '08:00')::timestamp AT TIME ZONE 'America/Fortaleza',
                           (current_date+20+time '10:00')::timestamp AT TIME ZONE 'America/Fortaleza', 99, 'Lotada');
```

- Criar 1 reserva válida, cancelar e mostrar o rastro `INSERT` + `CANCELAMENTO` em `log_reserva` (`BEGIN ... ROLLBACK`):

```sql
BEGIN;
WITH r AS (
  SELECT criar_reserva(1, 5, (current_date+20+time '14:00')::timestamp AT TIME ZONE 'America/Fortaleza',
                             (current_date+20+time '16:00')::timestamp AT TIME ZONE 'America/Fortaleza', 12, 'Demo') AS id
)
SELECT cancelar_reserva((SELECT id FROM r), 1, 'Teste oral');
SELECT operacao, dados_antigos->>'status' AS ant, dados_novos->>'status' AS novo, usuario_db
  FROM log_reserva ORDER BY id DESC LIMIT 2;
ROLLBACK;
```

### 8–10 min · Views, Materialized View e Consulta Analítica (**Aluno B**)
- Explicar diferença entre `v_agenda_dia` / `v_reservas_usuario` (tempo real) e `mv_ocupacao_mensal` (persistida + índice `UNIQUE` para `REFRESH MATERIALIZED VIEW CONCURRENTLY`).
- Mostrar o resultado de uma consulta com *window function* (Q4 em `analise/consultas_analiticas.md`: `RANK()` + `LAG()`):

```powershell
docker compose exec -T db psql -U postgres -d reservas -c "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ocupacao_mensal;" -c "SELECT count(*) AS total_reservas FROM reserva;"
```

### 10–13 min · Índices e `EXPLAIN (ANALYZE, BUFFERS)` Antes/Depois (**Aluno B**)
- Mostrar os prints [`analise/explain/print_indice_1.png`](../analise/explain/print_indice_1.png) e [`analise/explain/print_indice_2.png`](../analise/explain/print_indice_2.png) e os arquivos em `analise/explain/`.
- Destacar por que `sem_conflito` (GiST em `(sala_id, periodo)`) não cobria essas consultas e mostrar os ganhos reais:
  - Índice 1 (`idx_reserva_usuario_futuras`): `4.733 ms` / `207` buffers (`Seq Scan`) → `0.953 ms` / `6` buffers (`Bitmap Index Scan`).
  - Índice 2 (`idx_reserva_inicio`): `7.116 ms` / `208` buffers (`Sort` + `Seq Scan`) → `1.332 ms` / `50` buffers (`Index Scan`, eliminou o `Sort`).

### 13–16 min · Demonstração de Concorrência (`EXCLUDE` + `pg_stat_activity`) (**Aluno A**)
- **Terminal A (Sessão A):**
  ```sql
  \i /projeto/concorrencia/sessao_A.sql
  ```
- **Terminal B (Sessão B — trava esperando A):**
  ```sql
  \i /projeto/concorrencia/sessao_B.sql
  ```
- **Terminal C (Sessão C — prova do lock):**
  ```powershell
  docker compose exec -T db psql -U postgres -d reservas -c "SELECT pid, state, wait_event_type, wait_event, left(query, 65) AS query FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();"
  ```
- **Terminal A:** executar `COMMIT;` → Terminal B recebe imediatamente `RS010` (`Rolls back` em seguida).
- Mencionar também o `FOR NO KEY UPDATE` na linha de `usuario` contra *write skew* no limite de 3 reservas (e se houver tempo, rodar `python concorrencia/teste_concorrencia.py`).

### 16–18 min · Segurança (`app_reservas`) (**Aluno A**)
- Conectar como `app_reservas` e mostrar o bloqueio nas tabelas base e o funcionamento exclusivo da API:

```powershell
docker compose exec -T db psql -U app_reservas -d reservas -c "SELECT * FROM reserva LIMIT 1;"
docker compose exec -T db psql -U app_reservas -d reservas -c "SELECT * FROM v_agenda_dia LIMIT 3;" -c "SELECT taxa_ocupacao(5, current_date);"
```

### 18–20 min · Aplicação (Página Web + CLI) (**Aluno B**)
- Executar `python app/main.py --web`, abrir **`http://127.0.0.1:8000`** no navegador (ou `python app/main.py` no terminal):
  1. Listar salas (`v_salas_recursos`) / consultar agenda da sala `5` (`v_agenda_dia`);
  2. Criar reserva válida para usuário `1` na sala `5` e recarregar a agenda;
  3. Tentar criar reserva conflitante ou acima da capacidade (`qtd=99`) → mostrar o banner com a mensagem vinda direto do PostgreSQL (`✖ [RS010]` / `✖ [RS007]`);
  4. Cancelar a reserva criada e mostrar o sumiço imediato na agenda;
  5. Exibir o relatório de ocupação mensal (`mv_ocupacao_mensal`).

---

## 3. Protocolo do Ensaio Oral Cruzado (Subfase 12.4)

Antes da apresentação oficial, **Aluno A** e **Aluno B** devem realizar juntos este ensaio completo em duas rodadas:

### Parte 1 — Bateria de 15 Perguntas Sorteadas (para cada aluno)
Consultar as perguntas `P1`–`P65` na **Seção 7** de [`plano_implementacao_reservas.md`](../plano_implementacao_reservas.md), sorteando pelo menos 2 perguntas de cada tema por aluno:
- 2 de Modelagem/3FN (`P1`–`P9`)
- 2 de DDL/`EXCLUDE` (`P10`–`P16`)
- 3 de Triggers/Functions (`P17`–`P28`, `P64`)
- 2 de Views/Matviews (`P29`–`P33`)
- 2 de Consultas/Índices/`EXPLAIN` (`P34`–`P43`)
- 2 de Concorrência (`P44`–`P51`)
- 2 de Segurança/Aplicação/Crítica (`P52`–`P65`)
- **Rodada 1:** responder **sem olhar código ou colas**, explicando sempre com nomes reais de tabelas/objetos do projeto.
- **Rodada 2:** abrir `docs/estudo/roteiro_estudo_completo.md` e corrigir eventuais lacunas imediatamente.

### Parte 2 — Execução Individual Ao Vivo (obrigatória para cada aluno sozinho)
Cada integrante deve executar sozinho, sem auxílio do colega:
1. **`H2` (conflito direto na tabela):** fazer `INSERT` sobreposto como `postgres` dentro de `BEGIN ... ROLLBACK` e explicar por que o erro é `23P01` (`sem_conflito`) e não `RS010` (que só existe no `EXCEPTION` de `criar_reserva`).
2. **`H9` (duas sessões concorrentes):** executar `\i /projeto/concorrencia/sessao_A.sql` e `\i /projeto/concorrencia/sessao_B.sql` em dois terminais, consultar `pg_stat_activity` no terceiro e provar os dois desfechos (`COMMIT` → `RS010`; `ROLLBACK` → sucesso).
3. **Alteração dinâmica de regra no trigger (`H1`):** alterar `c_dur_max` de `'4 hours'` para `'3 hours'` via `CREATE OR REPLACE FUNCTION fn_regras_reserva()` (ou em `BEGIN ... ROLLBACK` / restaurando depois com `scripts/reset.sh`), tentar criar uma reserva de `3h30` esperando `RS005`, e provar que `app/` não mudou nenhuma linha.

*(Ao encerrar o ensaio, executar `docker compose exec -T db sh /projeto/scripts/reset.sh` para deixar o banco exatamente no estado padrão de entrega.)*
