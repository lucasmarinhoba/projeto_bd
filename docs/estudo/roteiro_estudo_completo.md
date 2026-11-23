# Roteiro de Estudo Completo — Avaliação Oral Individual

Consolidação sem repetições das colas de estudo das **Fases 0 a 12**, seguida do guia rápido das **9 demonstrações práticas ao vivo (`H1`–`H9`)**.

---

## 1. Setup, Roles e Arquitetura Geral (Fases 0, 10 e 11)

- **Dono `NOSUPERUSER` (`reservas_owner`):** funções `SECURITY DEFINER` e views executam com privilégios do seu dono. Se o dono fosse superusuário, qualquer falha daria acesso irrestrito ao cluster; usando `reservas_owner` (`NOSUPERUSER`, `NOLOGIN`), o risco fica isolado ao schema `reservas`.
- **Idempotência de `reset.sh`:** `sql/99_reset.sql` (`DROP SCHEMA reservas CASCADE`) roda **primeiro**, fora do glob `sql/0*.sql`. Roles (`reservas_owner`, `app_reservas`) são objetos globais do cluster (sobrevivem ao `DROP SCHEMA`) e por isso usam criação/alteração idempotente via bloco `DO ... IF NOT EXISTS`.
- **`search_path` e `timezone`:** fixados para `reservas, public` e `America/Fortaleza`, garantindo coerência no `EXCLUDE` (`btree_gist` no schema `public` ou acessível) e nas conversões locais de horário (`07:00–22:00` e fechamento de mês).
- **Princípio do menor privilégio (`app_reservas`):** não é superusuário, não cria tabelas (`USAGE` sem `CREATE`) e não possui `SELECT/INSERT/UPDATE/DELETE` em nenhuma das 6 tabelas base. Só enxerga as 4 views/matviews (que rodam com privilégios do dono, `security_invoker` desligado) e só executa as 3 functions da API após `REVOKE EXECUTE ... FROM PUBLIC` (necessário porque funções no PostgreSQL nascem executáveis por `PUBLIC`).
- **`SECURITY DEFINER` + `search_path` hijacking:** `criar_reserva`, `cancelar_reserva`, `taxa_ocupacao` e `fn_audit_reserva` fixam `SET search_path = reservas, pg_temp` para impedir sequestro por objetos homônimos em schemas temporários/públicos.
- **`session_user` vs `current_user`:** dentro de funções `SECURITY DEFINER`, `current_user` assume o dono (`reservas_owner`), enquanto `session_user` preserva quem abriu a conexão (`app_reservas` ou `postgres`), permitindo auditoria fiel em `log_reserva.usuario_db`.
- **Casca fina em `app/`:** apenas parsing de formato (`date.fromisoformat`, `time.fromisoformat`, `int`), SQL parametrizado com `%s` (imune a SQL injection), `conn.commit()`/`conn.rollback()` explícitos no `psycopg 3` (`autocommit=False`), e repasse literal de `e.diag.message_primary`. Se a duração máxima mudar de 4 h para 3 h no trigger, **zero linha** da aplicação muda.
- **Limitação assumida de segurança e evolução:** a aplicação informa o `usuario_id` sem autenticação individual por sessão; evolução natural é usar **Row-Level Security (RLS)** com `SET LOCAL app.usuario_id`.

---

## 2. Modelagem, 3FN e Integridade Declarativa (Fases 1 e 2)

- **Normalização (3FN):**
  - **1FN (atomicidade):** atributos multivalorados de equipamentos saíram de `sala` para `sala_recurso`. `tstzrange` é tipo escalar no PostgreSQL (atômico).
  - **2FN (sem dependência parcial):** `sala_recurso.quantidade` depende da chave composta inteira `(sala_id, recurso_id)`.
  - **3FN (sem dependência transitiva):** `reserva` armazena apenas `usuario_id` e `sala_id`, nunca nome do usuário nem capacidade da sala.
- **Atributos omitidos e desnormalização intencional:**
  - Status `CONCLUIDA` não é armazenado porque deriva do tempo (`status = 'ATIVA' AND upper(periodo) <= now()`); duração deriva de `upper(periodo) - lower(periodo)`.
  - `log_reserva` usa `jsonb` (`dados_antigos`/`dados_novos`) como **desnormalização intencional *append-only*** para congelar o snapshot exato da linha no instante do evento.
- **Chaves substitutas e `ON DELETE`:**
  - PKs são `GENERATED ALWAYS AS IDENTITY` (menores e imunes a trocas de matrícula/código), mantendo `matricula`, `email` e `codigo` como chaves candidatas `UNIQUE NOT NULL`.
  - `ON DELETE RESTRICT` em `reserva → usuario/sala`, `log_reserva → reserva` e `sala_recurso → recurso` preserva histórico e auditoria (exclusão lógica com `ativo`/`ativa = false`). `ON DELETE CASCADE` apenas em `sala_recurso → sala`, pois a associação não existe sem a sala.
- **ENUM vs DOMAIN vs tabela de domínio:** `ENUM` (`status_reserva`, `tipo_usuario`, `tipo_sala`) modela listas pequenas e estáveis sem exigir `JOIN`; `DOMAIN` (`email_t`, `qtd_positiva`) centraliza validações reutilizáveis entre várias colunas; tabela de domínio só compensa se houver metadados extras ou adição/remoção dinâmica frequente.
- **`EXCLUDE USING gist` + `btree_gist` + `[)`:**
  - Índice GiST parcial `(sala_id WITH =, periodo WITH &&) WHERE (status = 'ATIVA')`.
  - `btree_gist` adiciona suporte a `=` de inteiros (`sala_id`) dentro do GiST.
  - `WHERE (status = 'ATIVA')` garante que reservas canceladas liberem o horário imediatamente.
  - Intervalo meio-aberto `[)` garante que `08:00–10:00` e `10:00–12:00` sejam adjacentes sem falso conflito (forçado junto a `NOT isempty/lower_inf/upper_inf` em `ck_periodo_valido`).

---

## 3. Triggers, Functions, Carga Massiva e Views (Fases 3, 4, 5 e 6)

- **`BEFORE` vs `AFTER`:** `trg_regras_reserva` roda `BEFORE` para validar/barrar antes de gravar (retornando `NEW`; retornar `NULL` cancelaria silenciosamente); `trg_audit_reserva` roda `AFTER` para depender do `id` gerado (FK em `log_reserva`) e só auditar operações efetivadas (`RETURN NULL` é ignorado em `AFTER`).
- **Auditoria (`TG_OP`, `OLD`, `NEW`):** identifica `INSERT` (`dados_novos`), `UPDATE` comum e a transição `OLD.status = 'ATIVA' AND NEW.status = 'CANCELADA'` como `CANCELAMENTO`.
- **Function vs Procedure + Subtransação:** `criar_reserva` e `cancelar_reserva` são `FUNCTION`s para retornar valor (`id`) e manter atomicidade dentro da transação do chamador (diferente de `PROCEDURE` com `COMMIT` interno). O bloco `EXCEPTION WHEN exclusion_violation THEN` cria uma **subtransação (savepoint implícito)** e traduz `23P01` em `RS010`.
- **Regra em trigger vs function:** regras como capacidade, duração, funcionamento e limite de 3 futuras vivem no trigger (`BEFORE`) para valer por **defesa em profundidade** (tanto via `criar_reserva()` quanto via `INSERT`/`UPDATE` ou carga em massa).
- **`taxa_ocupacao` (`STABLE`):** lê tabelas (por isso não pode ser `IMMUTABLE`), mas retorna resultado estável no mesmo comando (`STABLE`); normaliza `p_mes::timestamp` no `date_trunc` para evitar deslocamento de fuso.
- **View vs Materialized View:** `v_agenda_dia` e `v_reservas_usuario` são views comuns (tempo real após cada reserva/cancelamento). `mv_ocupacao_mensal` persiste a agregação mensal e aceita `REFRESH MATERIALIZED VIEW CONCURRENTLY` graças ao índice `UNIQUE (sala_id, mes)` (que permite comparar linha a linha sem bloquear leituras). Como nenhuma reserva cruza a meia-noite, cada reserva pertence a um único mês em `America/Fortaleza`.
- **Seeds determinísticos (`06_seed_base.sql` e `07_seed_massa.sql`):** `setseed(0.42)` reproduz nomes e sorteios; `generate_series` + `CROSS JOIN LATERAL` + `AS MATERIALIZED` geram slots disjuntos (`07, 09, 11, 13, 15, 17, 19 h`), mantendo **triggers e `EXCLUDE` ligados** durante toda a carga de `13.013` reservas (com IDs de demonstração `usuario 1..4` e `sala 5` livres no futuro).

---

## 4. Consultas Analíticas, Índices e Concorrência (Fases 7, 8 e 9)

- **SQL Analítico:**
  - `WHERE` filtra tuplas antes do agrupamento; `HAVING` filtra grupos após `GROUP BY`.
  - `GROUP BY` colapsa linhas; *window functions* (`OVER (PARTITION BY ...)`) calculam sem colapsar linhas.
  - Em empate `(100, 100, 90)`: `RANK()` = `1, 1, 3`; `DENSE_RANK()` = `1, 1, 2`; `ROW_NUMBER()` = `1, 2, 3`.
  - Desde o PostgreSQL 12, CTEs simples não recursivas são *inlined* por padrão (`AS MATERIALIZED` força materialização); `count(*) FILTER (WHERE ...)` substitui `SUM(CASE ...)`.
- **Índices e `EXPLAIN (ANALYZE, BUFFERS)`:**
  - `sem_conflito` (`GiST` em `(sala_id, periodo)`) tem `sala_id` como líder e não ajuda buscas por `usuario_id` ou janelas globais sem sala.
  - Foram criados `idx_reserva_usuario_futuras` (`B-tree (usuario_id, lower(periodo)) WHERE status = 'ATIVA'`, reduzindo consulta do trigger de `4.733 ms` / `207` buffers para `0.953 ms` / `6` buffers) e `idx_reserva_inicio` (`B-tree (lower(periodo)) WHERE status = 'ATIVA'`, reduzindo busca ordenada de `7.116 ms` / `208` buffers com `Sort` para `1.332 ms` / `50` buffers com `Index Scan` sem `Sort`).
  - **Limites/custo:** índices consomem disco (`384 kB` + `160 kB`) e atualizam em `INSERT`/`UPDATE`; o planner prefere `Seq Scan` quando a seletividade é baixa, a tabela é minúscula ou faltam estatísticas (`ANALYZE`).
- **Transações e Concorrência:**
  - Funciona inteiramente em **`READ COMMITTED`** (snapshot por comando).
  - Na corrida por mesmo horário, a 2ª sessão bloqueia (`wait_event_type = Lock`, `wait_event = transactionid`) no índice GiST de `sem_conflito` até a 1ª dar `COMMIT` (2ª falha com `RS010`) ou `ROLLBACK` (2ª passa).
  - Na corrida pelo limite de 3 futuras (*write skew*), `PERFORM 1 FROM usuario WHERE id = NEW.usuario_id FOR NO KEY UPDATE` serializa reservas do mesmo usuário sem bloquear `FOR KEY SHARE` das FKs (como faria `FOR UPDATE`). Travar sempre na ordem `usuario → reserva` evita *deadlock* (`40P01`).

---

## 5. Colinha das 9 Demonstrações ao Vivo (`H1`–`H9`)

| # | Pedido do professor | Comando pronto no `psql` (`postgres`) |
|---|---|---|
| **H1** | Mudar duração máxima para 3 h e testar erro `RS005` | Editar constante `c_dur_max` em `fn_regras_reserva` (`CREATE OR REPLACE FUNCTION`), tentar `SELECT criar_reserva(1, 5, ..., '08:00'..'11:30', 10);` → `RS005` *(lembrar de restaurar `4 hours` depois)* |
| **H2** | Inserir reserva conflitante direto na tabela | `BEGIN; INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes) VALUES (1, 5, '[2027-05-10 08:00-03, 2027-05-10 10:00-03)', 10);` seguido de outro conflito `09:00-11:00` → erro `23P01` (`sem_conflito`); `ROLLBACK;` |
| **H3** | Mostrar log do cancelamento | `SELECT id, reserva_id, operacao, dados_antigos->>'status' AS ant, dados_novos->>'status' AS novo, usuario_db FROM log_reserva WHERE operacao = 'CANCELAMENTO' ORDER BY id DESC LIMIT 3;` |
| **H4** | Adicionar status `PENDENTE` ao ENUM | `ALTER TYPE status_reserva ADD VALUE 'PENDENTE';` *(explicar: no PG, o novo valor do ENUM só pode ser usado após o `COMMIT` da transação que executou o `ALTER TYPE`)* |
| **H5** | Provar zero reservas conflitantes no banco | `SELECT count(*) FROM reserva a JOIN reserva b ON a.sala_id = b.sala_id AND a.id < b.id AND a.periodo && b.periodo AND a.status = 'ATIVA' AND b.status = 'ATIVA';` → `0` |
| **H6** | Top 3 salas mais ocupadas do mês passado | `SELECT sala_codigo, horas_reservadas, taxa_ocupacao_pct FROM mv_ocupacao_mensal WHERE mes = date_trunc('month', (current_date - interval '1 month')::timestamp)::date ORDER BY taxa_ocupacao_pct DESC LIMIT 3;` |
| **H7** | Derrubar índice e comparar `EXPLAIN ANALYZE` | `BEGIN; DROP INDEX idx_reserva_inicio; EXPLAIN (ANALYZE, BUFFERS) ...; ROLLBACK;` *(mostra `Sort + Seq Scan` voltando sem perder o índice ao dar `ROLLBACK`!)* |
| **H8** | Explicar uma linha do trigger em voz alta | Ler qualquer linha de `sql/03_triggers.sql` explicando **o quê** faz, **por quê** (`BEFORE`, `FOR NO KEY UPDATE`, `AT TIME ZONE`) e **o que quebraria** sem ela |
| **H9** | Reproduzir corrida entre 2 sessões no terminal | Terminal 1: `\i /projeto/concorrencia/sessao_A.sql`; Terminal 2: `\i /projeto/concorrencia/sessao_B.sql`; Terminal 3: consulta `pg_stat_activity`; Terminal 1: `COMMIT;` ou `ROLLBACK;` |
