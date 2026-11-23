# Guia Completo de Testes por Fase (com "Viagem no Tempo" via Git)

Este guia reúne **todos os comandos de verificação e teste de cada fase (Fase 0 a Fase 12)**, incluindo os comandos de **`git checkout` ("voltar no tempo")** para testar qualquer fase isoladamente no estado exato em que ela foi construída, e a **saída esperada real** de cada execução.

> **Ambiente considerado:** Windows PowerShell na raiz do repositório (`projeto_bd`), com Docker Desktop ativo e Python 3.10+ (`psycopg[binary]`) instalado. O PostgreSQL 16 roda no container `reservas_db` (porta `5433` no host → `5432` no container).

---

## 1. Como funciona a "viagem no tempo" entre fases

O script [`scripts/reset.sh`](../scripts/reset.sh) executa `sql/99_reset.sql` (`DROP SCHEMA reservas CASCADE`) e, em seguida, aplica **todos** os arquivos `sql/0*.sql` presentes na pasta naquele momento.

- Se você rodar `reset.sh` na branch **`main` (estado final)**, o banco já sobe com **todas** as fases aplicadas de uma vez (tabelas + triggers + functions + views + `13.013` reservas + índices + roles).
- Se você quiser testar uma fase específica **isoladamente** (por exemplo: ver a Fase 2 sem seed, a Fase 3 com `reserva` vazia, a Fase 5 antes da carga massiva, ou a Fase 8 antes da criação dos índices em `08_indices.sql`), use o fluxo abaixo:

```powershell
# 0) Antes de viajar no tempo, garanta que não há alterações locais não commitadas:
git status --short

# 1) Voltar no tempo para o commit exato da fase desejada:
git checkout <HASH_DO_COMMIT>

# 2) Recriar o schema do zero usando apenas os SQLs que existiam naquela fase:
docker compose exec -T db sh /projeto/scripts/reset.sh

# 3) Executar os testes daquela fase...

# 4) Ao terminar, voltar para a entrega final na branch main e restaurar o banco completo:
git checkout main
docker compose exec -T db sh /projeto/scripts/reset.sh
```

> **Sobre o container e volumes:** todos os commits desde a Fase 0 usam o mesmo `docker-compose.yml` (`postgres:16`, porta `5433:5432` e volume `./:/projeto:ro`). As roles `reservas_owner` e `app_reservas` ficam no cluster PostgreSQL; se quiser simular uma máquina **100% virgem** (inclusive sem roles prévias no cluster), use `docker compose down -v` e depois `docker compose up -d --wait`.

---

## 2. Mapa de Commits por Fase

| Fase | Descrição | Commit (`git checkout`) | Precisa voltar no tempo para isolar? |
|---|---|---|---|
| **Pré** | Plano e especificação inicial | `daa4f7d` | Não |
| **Fase 0** | Setup (`docker-compose`, `reset.sh`, `00_setup.sql`) | `a8830c1` | Sim, se quiser testar apenas `00_setup.sql` (schema vazio) |
| **Fase 1** | Modelagem, DER e 3FN (`docs/`) | `c835264` | Opcional (arquivos em `docs/` continuam na `main`) |
| **Fase 2** | DDL e integridade declarativa (`01_tipos`, `02_tabelas`) | `17576eb` | Sim, se quiser testar sem triggers nem seed (`reserva` vazia) |
| **Fase 3** | Seed base (`06_seed_base.sql`: 20 salas, 8 recursos, 150 usuários) | `e3d0706` | Sim, se quiser ver exatamente `0` reservas antes das Fases 4/6 |
| **Fase 4A** | Triggers (`03_triggers.sql`) | `40baf8e` | Sim, se quiser testar triggers antes da criação de `04_functions.sql` |
| **Fase 4B** | Functions (`04_functions.sql`) e `tests/test_regras.sql` | `56ee0d3` | Opcional (`test_regras.sql` também roda direto na `main`) |
| **Fase 5** | Views e Materialized View (`05_views.sql`) | `1ac9a72` | Sim, se quiser ver as views vazias antes da carga da Fase 6 |
| **Fase 6** | Carga massiva (`07_seed_massa.sql`: ≥ 10 mil reservas) | `9a67db7` | Opcional (os mesmos `13.013` registros existem na `main`) |
| **Fase 7** | 5 Consultas Analíticas (`analise/consultas_analiticas.*`) | `802aea7` | Não (roda igual na `main`) |
| **Fase 8** | Índices (`08_indices.sql`) e `EXPLAIN (ANALYZE, BUFFERS)` | `90f2e5f` | Não obrigatório (na `main`, pode usar `DROP INDEX` temporário e restaurar com `reset.sh`) |
| **Fase 9** | Concorrência e transações (`concorrencia/`) | `0ed8bee` | Opcional (na `main`, já testa direto como `app_reservas`) |
| **Fase 10** | Segurança (`09_roles.sql` e `tests/test_seguranca.sql`) | `74a31c9` | Não (roda igual na `main`) |
| **Fase 11** | Aplicação CLI + Página Web (`app/`) | `ae89b75` | Não (roda igual na `main`) |
| **Fase 12** | Documentação final, roteiro e congelamento | `main` (tag `entrega`) | Estado final completo |

---

## 3. Testes Detalhados Fase a Fase

---

### Fase 0 — Setup do Ambiente

- **Objetivo:** provar que o container sobe saudável, o `reset.sh` é idempotente em banco vazio e populado, o fuso é `America/Fortaleza`, o `search_path` é `reservas, public`, a extensão `btree_gist` existe e `reservas_owner` não é superusuário.

#### Voltar no tempo para o commit da Fase 0
```powershell
git checkout a8830c1
```

#### Comandos de teste
```powershell
# 1) Subir container e aguardar healthcheck
docker compose up -d --wait

# 2) Testar idempotência do reset (2x seguidas)
docker compose exec -T db sh /projeto/scripts/reset.sh
docker compose exec -T db sh /projeto/scripts/reset.sh

# 3) Verificar timezone e search_path padrão da sessão
docker compose exec -T db psql -U postgres -d reservas -c "SHOW timezone;" -c "SHOW search_path;"

# 4) Verificar que reservas_owner existe e NÃO é superusuário (rolsuper = f, rolcanlogin = f)
docker compose exec -T db psql -U postgres -d reservas -c "SELECT rolname, rolsuper, rolcanlogin FROM pg_roles WHERE rolname = 'reservas_owner';"

# 5) Verificar dono do schema reservas e presença da extensão btree_gist
docker compose exec -T db psql -U postgres -d reservas -c "SELECT nspname, pg_catalog.pg_get_userbyid(nspowner) AS owner FROM pg_namespace WHERE nspname = 'reservas';" -c "SELECT extname FROM pg_extension WHERE extname = 'btree_gist';"
```

#### Saída esperada
```text
==> sql/99_reset.sql
==> sql/00_setup.sql
==> reset concluido sem erros

     TimeZone      
-------------------
 America/Fortaleza
(1 row)

   search_path   
-----------------
 reservas, public
(1 row)

    rolname     | rolsuper | rolcanlogin 
----------------+----------+-------------
 reservas_owner | f        | f
(1 row)

 nspname  |     owner      
----------+----------------
 reservas | reservas_owner
(1 row)

  extname   
------------
 btree_gist
(1 row)
```

---

### Fase 1 — Modelagem, DER e 3FN

- **Objetivo:** conferir que o DER conceitual (`DER_conceitual.png`), o DER lógico (`DER_logico.md`), a análise de 3FN (`modelagem_3fn.md`) e a cola de estudo (`fase1.md`) existem e cobrem todas as 6 entidades e regras de `ON DELETE`.

#### Voltar no tempo para o commit da Fase 1 (opcional)
```powershell
git checkout c835264
```

#### Comandos de teste
```powershell
# 1) Conferir existência e tamanho (> 0 bytes) dos artefatos de modelagem
Get-Item docs/DER_conceitual.png, docs/DER_logico.md, docs/modelagem_3fn.md, docs/estudo/fase1.md | Select-Object Name, Length

# 2) Confirmar cobertura das 6 tabelas no DER lógico e das formas normais/ON DELETE em modelagem_3fn.md
Select-String -Path docs/DER_logico.md -Pattern "USUARIO|SALA|RECURSO|SALA_RECURSO|RESERVA|LOG_RESERVA" | Out-String
Select-String -Path docs/modelagem_3fn.md -Pattern "1FN|2FN|3FN|ON DELETE|tstzrange" | Out-String
```

#### Saída esperada
- Os 4 arquivos listados possuem `Length > 0` (`DER_conceitual.png` com ~40 KB+).
- O `Select-String` em `docs/DER_logico.md` encontra os blocos das 6 entidades (`USUARIO`, `SALA`, `RECURSO`, `SALA_RECURSO`, `RESERVA`, `LOG_RESERVA`).
- O `Select-String` em `docs/modelagem_3fn.md` lista as ocorrências de `1FN`, `2FN`, `3FN`, `ON DELETE` e `tstzrange`.

---

### Fase 2 — DDL e Integridade Declarativa

- **Objetivo:** verificar os 3 ENUMs, 2 DOMAINs, 6 tabelas pertencentes a `reservas_owner`, a constraint `sem_conflito` (`EXCLUDE USING gist`) e os 8+ cenários de integridade declarativa **sem triggers** (em `17576eb`, `03_triggers.sql` ainda não existe).

#### Voltar no tempo para o commit da Fase 2
```powershell
git checkout 17576eb
docker compose exec -T db sh /projeto/scripts/reset.sh
```

#### Comandos de teste
```powershell
# 1) Listar tipos/domínios e tabelas do schema reservas
docker compose exec -T db psql -U postgres -d reservas -c "\dT+ reservas.*" -c "\dt+ reservas.*"

# 2) Inspecionar estrutura e constraints da tabela reserva
docker compose exec -T db psql -U postgres -d reservas -c "\d reservas.reserva"

# 3) Executar a suíte de testes de integridade declarativa (test_integridade.sql)
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d reservas -f /projeto/tests/test_integridade.sql
```

#### Saída esperada
```text
# (no reset.sh desta fase rodam apenas 00_setup.sql, 01_tipos.sql e 02_tabelas.sql)
==> sql/99_reset.sql
==> sql/00_setup.sql
==> sql/01_tipos.sql
==> sql/02_tabelas.sql
==> reset concluido sem erros

# Trecho esperado em "\d reservas.reserva":
Check constraints:
    "ck_cancelamento_coerente" CHECK ((status = 'CANCELADA'::status_reserva) = (cancelada_em IS NOT NULL))
    "ck_periodo_valido" CHECK (NOT isempty(periodo) AND NOT lower_inf(periodo) AND NOT upper_inf(periodo) AND lower_inc(periodo) AND NOT upper_inc(periodo))
    "sem_conflito" EXCLUDE USING gist (sala_id WITH =, periodo WITH &&) WHERE (status = 'ATIVA'::status_reserva)

# Saída esperada de test_integridade.sql:
BEGIN
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 1: e-mail invalido bloqueado pelo DOMAIN email_t (23514)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 2: capacidade = 0 bloqueada pelo DOMAIN qtd_positiva (23514)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 3: matricula duplicada bloqueada por UNIQUE (23505)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 4a: periodo vazio bloqueado por ck_periodo_valido (23514)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 4b: periodo infinito bloqueado por ck_periodo_valido (23514)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 4c: periodo fechado [] bloqueado por ck_periodo_valido (23514)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 5: CANCELADA sem cancelada_em bloqueada por ck_cancelamento_coerente (23514)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 6: sobreposicao de reservas ATIVAS bloqueada por EXCLUDE sem_conflito (23P01)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 7: reserva ATIVA sobreposta a uma CANCELADA foi aceita
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 8: reserva adjacente 10:00-12:00 apos 08:00-10:00 aceita pelo intervalo [)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 9a: ON DELETE RESTRICT impediu apagar sala com reserva (23503)
psql:/projeto/tests/test_integridade.sql:155: NOTICE:  OK 9b: ON DELETE CASCADE removeu associacoes em sala_recurso ao apagar sala sem reserva
DO
ROLLBACK
```

---

### Fase 3 — Seed Base

- **Objetivo:** validar a carga determinística inicial (`20` salas, `8` recursos, `89` associações `sala_recurso`, `150` usuários — `120 ALUNO`, `25 PROFESSOR`, `5 ADMIN`), os `4` usuários de demonstração (`IDs 1..4`) e a sala de demonstração (`ID 5`, `A-105`), com `reserva` ainda vazia (`0` linhas) no commit da Fase 3.

#### Voltar no tempo para o commit da Fase 3
```powershell
git checkout e3d0706
docker compose exec -T db sh /projeto/scripts/reset.sh
```

#### Comandos de teste
```powershell
# 1) Conferir contagens de todas as tabelas base (e que reserva = 0 neste ponto do tempo)
docker compose exec -T db psql -U postgres -d reservas -c "SELECT 'sala' AS tabela, count(*) FROM sala UNION ALL SELECT 'recurso', count(*) FROM recurso UNION ALL SELECT 'sala_recurso', count(*) FROM sala_recurso UNION ALL SELECT 'usuario', count(*) FROM usuario UNION ALL SELECT 'reserva', count(*) FROM reserva;"

# 2) Conferir distribuição de salas e usuários por tipo
docker compose exec -T db psql -U postgres -d reservas -c "SELECT tipo, count(*), min(capacidade), max(capacidade) FROM sala GROUP BY tipo ORDER BY tipo;" -c "SELECT tipo, count(*) FROM usuario GROUP BY tipo ORDER BY tipo;"

# 3) Conferir usuários de demonstração fixos (IDs 1..4) e sala de demonstração (ID 5)
docker compose exec -T db psql -U postgres -d reservas -c "SELECT id, matricula, nome, tipo FROM usuario WHERE id IN (1,2,3,4) ORDER BY id;" -c "SELECT id, codigo, nome, tipo, capacidade FROM sala WHERE id = 5;"
```

#### Saída esperada
```text
    tabela    | count 
--------------+-------
 sala         |    20
 recurso      |     8
 sala_recurso |    89
 usuario      |   150
 reserva      |     0
(5 rows)

    tipo     | count | min | max 
-------------+-------+-----+-----
 SALA        |    12 |  25 |  80
 LABORATORIO |     8 |  20 |  45
(2 rows)

   tipo    | count 
-----------+-------
 ALUNO     |   120
 PROFESSOR |    25
 ADMIN     |     5
(3 rows)

 id | matricula |                 nome                  |   tipo    
----+-----------+---------------------------------------+-----------
  1 | 20260001  | Lucas Marinho (Demo Aluno 1)          | ALUNO
  2 | 20260002  | Beatriz Costa (Demo Aluno 2)          | ALUNO
  3 | PROF0001  | Prof. Carlos Eduardo (Demo Professor) | PROFESSOR
  4 | ADM0001   | Helena Souza (Demo Admin)             | ADMIN
(4 rows)

 id | codigo |            nome            | tipo | capacidade 
----+--------+----------------------------+------+------------
  5 | A-105  | Sala de Demonstracao A-105 | SALA |         40
(1 row)
```

---

### Fase 4A — Triggers (Auditoria e Regras de Negócio)

- **Objetivo:** validar que os 2 triggers (`trg_audit_reserva` AFTER e `trg_regras_reserva` BEFORE) estão ativos em `reserva`, que um `INSERT` direto gera `INSERT` em `log_reserva`, e que uma violação direta na tabela (ex.: duração > 4 h) é barrada com `RS005` mesmo antes de existirem as functions da Fase 4B.

#### Voltar no tempo para o commit da Fase 4A
```powershell
git checkout 40baf8e
docker compose exec -T db sh /projeto/scripts/reset.sh
```

#### Comandos de teste
```powershell
# 1) Listar triggers na tabela reserva (ambos com tgenabled = 'O')
docker compose exec -T db psql -U postgres -d reservas -c "SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid = 'reservas.reserva'::regclass AND NOT tgisinternal ORDER BY tgname;"

# 2) Testar auditoria automática no INSERT (transação revertida por ROLLBACK)
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d reservas -c "BEGIN; INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade) VALUES (1, 5, tstzrange((current_date+5+time '08:00') AT TIME ZONE 'America/Fortaleza', (current_date+5+time '10:00') AT TIME ZONE 'America/Fortaleza', '[)'), 10, 'Teste 4A'); SELECT operacao, dados_novos->>'status' AS status_novo FROM log_reserva ORDER BY id DESC LIMIT 1; ROLLBACK;"

# 3) Provocar RS005 direto na tabela (duração 5h > 4h) -> deve falhar com SQLSTATE RS005
docker compose exec -T db psql -U postgres -d reservas -c "INSERT INTO reserva (usuario_id, sala_id, periodo, qtd_participantes, finalidade) VALUES (1, 5, tstzrange((current_date+5+time '08:00') AT TIME ZONE 'America/Fortaleza', (current_date+5+time '13:00') AT TIME ZONE 'America/Fortaleza', '[)'), 10, 'Falha 5h');"
```

#### Saída esperada
```text
       tgname       | tgenabled 
--------------------+-----------
 trg_audit_reserva  | O
 trg_regras_reserva | O
(2 rows)

operacao | status_novo 
----------+-------------
 INSERT   | ATIVA
(1 row)
ROLLBACK

# Passo 3 (erro esperado):
ERROR:  Duracao invalida (05:00:00). A reserva deve durar entre 00:30:00 e 04:00:00.
CONTEXT:  PL/pgSQL function fn_regras_reserva() line 26 at RAISE
```

---

### Fase 4B — Functions e Suíte `test_regras.sql` (`RS001`–`RS014`)

- **Objetivo:** verificar que as 3 functions da API (`criar_reserva`, `cancelar_reserva`, `taxa_ocupacao`) pertencem a `reservas_owner`, são `SECURITY DEFINER`, `taxa_ocupacao` é `STABLE`, e todos os 14 SQLSTATEs `RS001`–`RS014` + fluxo positivo + auditoria passam em `tests/test_regras.sql`.

#### Voltar no tempo para o commit da Fase 4B (opcional — também roda igual na `main`)
```powershell
git checkout 56ee0d3
docker compose exec -T db sh /projeto/scripts/reset.sh
```

#### Comandos de teste
```powershell
# 1) Inspecionar proprietário, SECURITY DEFINER (prosecdef=t) e volatilidade das 3 functions
docker compose exec -T db psql -U postgres -d reservas -c "SELECT proname, pg_get_userbyid(proowner) AS owner, prosecdef, provolatile FROM pg_proc WHERE pronamespace = 'reservas'::regnamespace AND proname IN ('criar_reserva','cancelar_reserva','taxa_ocupacao') ORDER BY proname;"

# 2) Executar todos os testes de regras (RS001..RS014 + criação + auditoria + cancelamento + taxa_ocupacao)
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d reservas -f /projeto/tests/test_regras.sql
```

#### Saída esperada
```text
     proname      |     owner      | prosecdef | provolatile 
------------------+----------------+-----------+-------------
 cancelar_reserva | reservas_owner | t         | v
 criar_reserva    | reservas_owner | t         | v
 taxa_ocupacao    | reservas_owner | t         | s
(3 rows)

# Saída de test_regras.sql:
BEGIN
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS001: periodo invalido rejeitado
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS002: reserva no passado rejeitada
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS003: usuario inativo/inexistente rejeitado
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS004: sala inativa/inexistente rejeitada
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS005: duracao < 30 min e > 4 h rejeitadas
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS006: horario fora de 07:00-22:00 e virada de dia rejeitados
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS007: capacidade excedida rejeitada
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS008: limite de 3 reservas ativas futuras respeitado
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS009: reativacao de reserva cancelada bloqueada
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS010: conflito de horario traduzido de 23P01 para RS010
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS011: cancelamento de reserva inexistente rejeitado
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS012: cancelamento sem permissao rejeitado
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS013: duplo cancelamento rejeitado
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK RS014: cancelamento de reserva ja iniciada rejeitado
psql:/projeto/tests/test_regras.sql:324: NOTICE:  OK fluxo positivo + auditoria (INSERT e CANCELAMENTO) + cancelamento por ADMIN + taxa_ocupacao = 2.15%
DO
ROLLBACK
```

---

### Fase 5 — Views e Materialized View

- **Objetivo:** validar `v_agenda_dia`, `v_reservas_usuario`, `v_salas_recursos` e `mv_ocupacao_mensal` (com índice `UNIQUE` `ux_mv_ocupacao_mensal_sala_mes` para `REFRESH CONCURRENTLY`), além da igualdade 100% entre `mv_ocupacao_mensal.taxa_ocupacao_pct` e `taxa_ocupacao(sala_id, mes)`.

#### A) Voltar no tempo para o commit da Fase 5 (antes da carga massiva — matview vazia/0 reservas)
```powershell
git checkout 1ac9a72
docker compose exec -T db sh /projeto/scripts/reset.sh
```

#### B) Validar com o volume completo (na `main` ou após a Fase 6)
```powershell
# 1) Listar views e materialized views do schema reservas
docker compose exec -T db psql -U postgres -d reservas -c "\dv+ reservas.*" -c "\dm+ reservas.*"

# 2) Testar REFRESH MATERIALIZED VIEW CONCURRENTLY (exige o índice UNIQUE em (sala_id, mes))
docker compose exec -T db psql -U postgres -d reservas -c "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ocupacao_mensal;"

# 3) Verificar consistência matemática entre mv_ocupacao_mensal e taxa_ocupacao() (deve retornar 0)
docker compose exec -T db psql -U postgres -d reservas -c "SELECT count(*) AS divergencias FROM mv_ocupacao_mensal mv WHERE mv.taxa_ocupacao_pct <> taxa_ocupacao(mv.sala_id, mv.mes);"

# 4) Amostra das 4 views na prática
docker compose exec -T db psql -U postgres -d reservas -c "SELECT * FROM v_salas_recursos LIMIT 5;" -c "SELECT * FROM mv_ocupacao_mensal ORDER BY mes DESC, taxa_ocupacao_pct DESC LIMIT 5;"
```

#### Saída esperada (na `main` / após Fase 6)
```text
# \dv+ lista v_agenda_dia, v_reservas_usuario, v_salas_recursos (dono reservas_owner)
# \dm+ lista mv_ocupacao_mensal (dono reservas_owner)

REFRESH MATERIALIZED VIEW

 divergencias 
--------------
            0
(1 row)
```
*(No commit `1ac9a72`, `mv_ocupacao_mensal` mostra `total_reservas = 0` e `taxa_ocupacao_pct = 0.00` em todas as salas porque a carga massiva só entra na Fase 6; a partir da Fase 6, são `280` linhas na matview — 20 salas × 14 meses — com `divergencias = 0`).*

---

### Fase 6 — Carga Massiva (`07_seed_massa.sql`)

- **Objetivo:** comprovar que a carga massiva gerou `>= 10.000` reservas com os triggers e `EXCLUDE` **ativos**, ~8% canceladas, `>= 1` evento em `log_reserva` para cada reserva, **`0` conflitos**, **`0` violações do limite de 3 futuras**, e **`0` reservas futuras na sala `5` e usuários `1..4`**.

#### Voltar no tempo para o commit da Fase 6 (opcional — na `main` o conteúdo de `07_seed_massa.sql` é idêntico)
```powershell
git checkout 9a67db7
docker compose exec -T db sh /projeto/scripts/reset.sh
```

#### Comandos de teste
```powershell
# 1) Conferir volume por status em reserva e por operação em log_reserva
docker compose exec -T db psql -U postgres -d reservas -c "SELECT status, count(*) FROM reserva GROUP BY ROLLUP(status) ORDER BY status NULLS LAST;" -c "SELECT operacao, count(*) FROM log_reserva GROUP BY ROLLUP(operacao) ORDER BY operacao NULLS LAST;"

# 2) Prova matemática de ZERO conflitos entre reservas ATIVAS (deve ser 0)
docker compose exec -T db psql -U postgres -d reservas -c "SELECT count(*) AS conflitos FROM reserva a JOIN reserva b ON a.sala_id = b.sala_id AND a.id < b.id AND a.periodo && b.periodo AND a.status = 'ATIVA' AND b.status = 'ATIVA';"

# 3) Prova de ZERO violações do limite de 3 reservas futuras e isolamento dos IDs de demo (devem ser 0 e 0)
docker compose exec -T db psql -U postgres -d reservas -c "SELECT count(*) AS violacoes_limite FROM (SELECT usuario_id FROM reserva WHERE status = 'ATIVA' AND lower(periodo) > now() GROUP BY usuario_id HAVING count(*) > 3) t;" -c "SELECT count(*) AS reservas_futuras_demo FROM reserva WHERE lower(periodo) > now() AND (sala_id = 5 OR usuario_id IN (1,2,3,4));"
```

#### Saída esperada
```text
  status   | count 
-----------+-------
 ATIVA     | 11984
 CANCELADA |  1029
           | 13013
(3 rows)

   operacao   | count 
--------------+-------
 INSERT       | 13013
 CANCELAMENTO |  1029
              | 14042
(3 rows)

 conflitos 
-----------
         0
(1 row)

 violacoes_limite 
------------------
                0
(1 row)

 reservas_futuras_demo 
-----------------------
                     0
(1 row)
```

---

### Fase 7 — Cinco Consultas Analíticas

- **Objetivo:** rodar Q1 (`JOIN + GROUP BY + HAVING`), Q2 (subconsulta escalar no `HAVING`), Q3 (`CTE + FILTER`), Q4 (`RANK + LAG`) e Q5 (`CTE + DENSE_RANK`) em `< 2000 ms` cada.

#### Voltar no tempo para o commit da Fase 7 (opcional — na `main` os arquivos são idênticos)
```powershell
git checkout 802aea7
```

#### Comandos de teste
```powershell
# 1) Rodar todas as 5 consultas com cronômetro (\timing on)
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d reservas -c "\timing on" -f /projeto/analise/consultas_analiticas.sql

# 2) Conferir presença de Q1..Q5 e documentação no .md
Select-String -Path analise/consultas_analiticas.md -Pattern "^## Q[1-5]|HAVING|FILTER|RANK|DENSE_RANK|LAG" | Out-String
```

#### Saída esperada
- Q1 (`15 rows`): ~`281 ms`
- Q2 (`9 rows`): ~`77 ms`
- Q3 (`21 rows`): ~`89 ms`
- Q4 (`20 rows`, mostra empates em `3º` e `10º` lugar em `2026-10`): ~`58 ms`
- Q5 (`6 rows`, pódio de `ALUNO` e `PROFESSOR`): ~`33 ms`
- Todas executam em menos de `300 ms` (muito abaixo do limite de `2000 ms`).

---

### Fase 8 — Índices e `EXPLAIN (ANALYZE, BUFFERS)`

- **Objetivo:** comprovar o ganho real de plano de execução, tempo e páginas lidas (`shared hit`) entre o cenário **sem** os índices de `sql/08_indices.sql` e **com** os índices ativos.

#### Como testar o cenário "ANTES" (duas opções)

**Opção A — Via "Viagem no Tempo" (voltando para a Fase 7 `802aea7`, antes de `08_indices.sql` existir):**
```powershell
git checkout 802aea7
docker compose exec -T db sh /projeto/scripts/reset.sh
```

**Opção B — Direto na `main` (dropando os dois índices temporariamente na sessão):**
```powershell
docker compose exec -T db psql -U postgres -d reservas -c "DROP INDEX IF EXISTS idx_reserva_usuario_futuras, idx_reserva_inicio;" -c "VACUUM ANALYZE reserva;"
```

#### Medir o "ANTES" (3x e observar a última com cache aquecido)
```powershell
# Consulta 1 (ANTES -> esperado Seq Scan on reserva, ~207 buffers, ~4.7 ms)
docker compose exec -T db psql -U postgres -d reservas -c "EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM reserva WHERE usuario_id = 54 AND status = 'ATIVA' AND lower(periodo) > '2026-11-23 12:00:00-03'::timestamptz;"

# Consulta 2 (ANTES -> esperado Sort + Seq Scan on reserva, ~208 buffers, ~7.1 ms)
docker compose exec -T db psql -U postgres -d reservas -c "EXPLAIN (ANALYZE, BUFFERS) SELECT id, usuario_id, sala_id, periodo, qtd_participantes FROM reserva WHERE status = 'ATIVA' AND lower(periodo) >= '2026-10-01 00:00:00-03'::timestamptz AND lower(periodo) < '2026-10-08 00:00:00-03'::timestamptz ORDER BY lower(periodo);"
```

#### Aplicar os índices ("DEPOIS") — voltando para `90f2e5f` ou `main`
```powershell
# Se usou Opção A (802aea7):
git checkout 90f2e5f   # (ou git checkout main)
docker compose exec -T db sh /projeto/scripts/reset.sh

# Se usou Opção B (direto na main):
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d reservas -f /projeto/sql/08_indices.sql
docker compose exec -T db psql -U postgres -d reservas -c "VACUUM ANALYZE reserva;"
```

#### Medir o "DEPOIS" e conferir arquivos/tamanhos
```powershell
# Consulta 1 (DEPOIS -> esperado Bitmap Heap Scan + Bitmap Index Scan em idx_reserva_usuario_futuras, ~6 buffers, < 1 ms)
docker compose exec -T db psql -U postgres -d reservas -c "EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM reserva WHERE usuario_id = 54 AND status = 'ATIVA' AND lower(periodo) > '2026-11-23 12:00:00-03'::timestamptz;"

# Consulta 2 (DEPOIS -> esperado Index Scan using idx_reserva_inicio SEM nó Sort, ~50 buffers, ~1.3 ms)
docker compose exec -T db psql -U postgres -d reservas -c "EXPLAIN (ANALYZE, BUFFERS) SELECT id, usuario_id, sala_id, periodo, qtd_participantes FROM reserva WHERE status = 'ATIVA' AND lower(periodo) >= '2026-10-01 00:00:00-03'::timestamptz AND lower(periodo) < '2026-10-08 00:00:00-03'::timestamptz ORDER BY lower(periodo);"

# Listar todos os 4 índices da tabela reserva e seus tamanhos
docker compose exec -T db psql -U postgres -d reservas -c "SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS tamanho FROM pg_indexes WHERE schemaname = 'reservas' AND tablename = 'reserva' ORDER BY indexname;"

# Conferir arquivos e prints salvos da Fase 8
Get-Item analise/explain/antes_*.txt, analise/explain/depois_*.txt, analise/explain/print_indice_*.png, analise/explain/analise.md | Select-Object Name, Length
```

#### Saída esperada
- **Índices em `reserva`:** `idx_reserva_inicio` (`160 kB`), `idx_reserva_usuario_futuras` (`384 kB`), `reserva_pkey` (`304 kB`), `sem_conflito` (`1080 kB`).
- **Consulta 1:** `Seq Scan` (`4.733 ms`, `207` buffers, `13.012` descartadas) → `Bitmap Index Scan` em `idx_reserva_usuario_futuras` (`0.953 ms`, `6` buffers, `0` descartadas).
- **Consulta 2:** `Sort` + `Seq Scan` (`7.116 ms`, `208` buffers, `12.780` descartadas) → `Index Scan using idx_reserva_inicio` sem `Sort` (`1.332 ms`, `50` buffers, `0` descartadas).

---

### Fase 9 — Concorrência e Transações

- **Objetivo:** provar o bloqueio entre transações concorrentes no `EXCLUDE USING gist` (`wait_event_type = Lock`, `wait_event = transactionid`), a resolução após `COMMIT`/`ROLLBACK` e a prevenção de *write skew* com `FOR NO KEY UPDATE`.

#### Voltar no tempo para o commit da Fase 9 (opcional — na `main` também funciona e já usa `app_reservas`)
```powershell
git checkout 0ed8bee
```

#### A) Teste automatizado (20 threads × 10 baterias + 10 threads no limite de 3 futuras)
```powershell
# 1) Resetar o banco antes para deixar os IDs de demo 100% limpos
docker compose exec -T db sh /projeto/scripts/reset.sh

# 2) Rodar o script automatizado de concorrência
python concorrencia/teste_concorrencia.py

# 3) Confirmar que zero usuários passaram de 3 reservas futuras
docker compose exec -T db psql -U postgres -d reservas -c "SELECT count(*) AS violacoes_limite FROM (SELECT usuario_id FROM reserva WHERE status = 'ATIVA' AND lower(periodo) > now() GROUP BY usuario_id HAVING count(*) > 3) t;"
```

#### Saída esperada (teste automatizado)
```text
=== Cenario 3: 10 baterias x 20 threads (role=app_reservas) ===
  Bateria 01/10 OK: 1 sucesso (reserva_id=...), 19 RS010, sobrepostas no banco=1
  ...
  Bateria 10/10 OK: 1 sucesso (reserva_id=...), 19 RS010, sobrepostas no banco=1
=== Cenario 2 (automatizado): corrida no limite de 3 reservas futuras ===
  Corrida limite OK: usuario 2 -> 1 sucesso, 9 RS008, total futuras=3
TODOS OS TESTES DE CONCORRENCIA PASSARAM.

 violacoes_limite 
------------------
                0
(1 row)
```
*(No commit `0ed8bee`, o cabeçalho exibe `role=postgres`; após a Fase 10 exibe automaticamente `role=app_reservas`.)*

#### B) Reprodução manual em 3 terminais PowerShell (`psql`)
```powershell
# Preparação (sempre resetar antes para não haver resíduo de testes anteriores):
docker compose exec -T db sh /projeto/scripts/reset.sh
```
- **Terminal 1 (Sessão A):**
  ```powershell
  docker compose exec db psql -U postgres -d reservas
  ```
  ```sql
  \i /projeto/concorrencia/sessao_A.sql
  -- Aguardar antes de dar COMMIT ou ROLLBACK!
  ```
- **Terminal 2 (Sessão B — ficará travada esperando A):**
  ```powershell
  docker compose exec db psql -U postgres -d reservas
  ```
  ```sql
  \i /projeto/concorrencia/sessao_B.sql
  ```
- **Terminal 3 (Sessão C — prova do lock em `pg_stat_activity` e `pg_locks`):**
  ```powershell
  docker compose exec -T db psql -U postgres -d reservas -c "SELECT pid, state, wait_event_type, wait_event, left(query, 65) AS query FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();" -c "SELECT pid, locktype, mode, granted FROM pg_locks WHERE NOT granted OR locktype = 'transactionid' ORDER BY granted, pid;"
  ```
  **Saída esperada na Sessão C:** Sessão B aparece com `state = active`, `wait_event_type = Lock`, `wait_event = transactionid` e `pg_locks` mostra `granted = f` esperando a transação de A.
- **Desfecho no Terminal 1:** digite `COMMIT;` (a Sessão B destrava imediatamente com `ERROR: Conflito de horario...`) **ou** `ROLLBACK;` (a Sessão B destrava imediatamente e cria a reserva com sucesso).

---

### Fase 10 — Segurança (`app_reservas`)

- **Objetivo:** provar o princípio do menor privilégio: a role `app_reservas` é barrada com `42501` (`permission denied`) ao tentar acessar diretamente qualquer das 6 tabelas ou criar tabelas, e só consegue ler as 4 views e executar as 3 functions da API (`criar_reserva`, `cancelar_reserva`, `taxa_ocupacao`).

#### Voltar no tempo para o commit da Fase 10 (opcional — na `main` é idêntico)
```powershell
git checkout 74a31c9
```

#### Comandos de teste
```powershell
# 1) Provar idempotência de 09_roles.sql rodando o reset 2x seguidas
docker compose exec -T db sh /projeto/scripts/reset.sh
docker compose exec -T db sh /projeto/scripts/reset.sh

# 2) Executar a suíte de segurança conectado COMO app_reservas
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U app_reservas -d reservas -f /projeto/tests/test_seguranca.sql

# 3) Tentativa negativa direta fora do bloco DO (deve falhar com permission denied)
docker compose exec -T db psql -U app_reservas -d reservas -c "SELECT * FROM reserva LIMIT 1;"

# 4) Tentativa positiva direta como app_reservas (deve funcionar)
docker compose exec -T db psql -U app_reservas -d reservas -c "SELECT * FROM v_agenda_dia LIMIT 3;" -c "SELECT taxa_ocupacao(1, current_date);"
```

#### Saída esperada
```text
# Passo 2 (test_seguranca.sql):
BEGIN
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK sessao autenticada como app_reservas
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK declarativo: zero privilegios diretos nas 6 tabelas base
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK declarativo: sem CREATE no schema reservas
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK declarativo: SELECT nas 4 views e EXECUTE apenas nas 3 functions da API
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK bloqueio: SELECT em reserva negado (42501)
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK bloqueio: INSERT direto em reserva negado (42501)
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK bloqueio: UPDATE direto em tabelas negado (42501)
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK bloqueio: DELETE direto em tabelas negado (42501)
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK bloqueio: SELECT em log_reserva negado (42501)
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK bloqueio: CREATE TABLE no schema reservas negado (42501)
psql:/projeto/tests/test_seguranca.sql:118: NOTICE:  OK permissoes: views, criar_reserva (id=...), cancelar_reserva e taxa_ocupacao (... %) executam como app_reservas
DO
ROLLBACK

# Passo 3 (erro esperado):
ERROR:  permission denied for table reserva

# Passo 4:
# Retorna até 3 linhas de v_agenda_dia e a porcentagem numérica da sala 1.
```

---

### Fase 11 — Aplicação CLI e Página Web (`app/`)

- **Objetivo:** provar que a aplicação é uma "casca fina" conectada exclusivamente como `app_reservas`, com zero ORM, zero SQL interpolado e zero regra de negócio no Python, e que tanto a CLI quanto a Página Web funcionam ponta a ponta.

#### Voltar no tempo para o commit da Fase 11 (opcional — na `main` o código de `app/` é o mesmo)
```powershell
git checkout ae89b75
```

#### Comandos de teste
```powershell
# 1) Garantir zero ORM e zero SQL por f-string/.format em app/ (não pode retornar nenhuma linha)
Select-String -Path app/*.py -Pattern "sqlalchemy|peewee|tortoise|django|prisma|f"".*SELECT|f'.*SELECT|\.format\(.*SELECT"

# 2) Inspecionar palavras de regra em app/ (apenas rótulos de UI e SQL/docstrings, zero "if" de regra)
Select-String -Path app/*.py -Pattern "capacidade|conflito|limite|duracao"

# 3) Resetar o banco e rodar o smoke test automatizado (testa CLI + HTTP GET/POST + erros RS005..RS012)
docker compose exec -T db sh /projeto/scripts/reset.sh
python app/main.py --smoke-test

# 4) Subir a Página Web interativa no navegador (Ctrl+C no terminal para encerrar):
python app/main.py --web
# Depois abra http://127.0.0.1:8000 no navegador

# 5) Ou abrir a CLI interativa no terminal:
python app/main.py
```

#### Saída esperada (`--smoke-test`)
```text
=== Smoke Test E2E (CLI + Web) como app_reservas ===
OK sessao: user=app_reservas, tz=America/Fortaleza
OK criar_reserva: id=...
OK v_agenda_dia: reserva ... encontrada
-- Provocando erros do banco via app (mensagens repassadas): --
✖ [RS005] Duracao invalida (00:15:00). A reserva deve durar entre 00:30:00 e 04:00:00.
✖ [RS006] Fora do horario de funcionamento (07:00:00-22:00:00) ou atravessa a meia-noite.
✖ [RS007] Capacidade excedida: a sala comporta 40 pessoas e foram informadas 99.
✖ [RS010] Conflito de horario: a sala 5 ja esta reservada em parte do periodo pedido.
✖ [RS008] Limite atingido: o usuario ja possui 3 reservas futuras ativas (maximo 3).
✖ [RS012] Permissao negada: apenas o dono da reserva ou um ADMIN pode cancela-la.
OK cancelar_reserva: reservas canceladas e removidas de v_agenda_dia
OK mv_ocupacao_mensal: 20 salas listadas para 2026-11
OK web.py: GET / e POST /criar renderizaram pagina HTML e erro RS007 do banco (porta ...)
SMOKE TEST FASE 11 PASSOU.
```

---

### Fase 12 — Revisão Geral de Entrega (Estado Final `main` / tag `entrega`)

- **Objetivo:** validar o repositório congelado ponta a ponta em uma única sequência após voltar para `main` (ou `git checkout entrega`).

#### Voltar para o estado final (caso tenha viajado no tempo)
```powershell
git checkout main
```

#### Comandos de teste completos da entrega final
```powershell
# 1) Reset completo do zero (recria todas as fases 0..10 em ordem)
docker compose exec -T db sh /projeto/scripts/reset.sh

# 2) Executar toda a suíte SQL (test_integridade + test_regras + test_seguranca)
docker compose exec -T db sh /projeto/scripts/test.sh

# 3) Teste automatizado de concorrência (20 threads x 10 baterias + corrida de limite)
python concorrencia/teste_concorrencia.py

# 4) Smoke test E2E da aplicação (CLI + Página Web)
python app/main.py --smoke-test

# 5) Conferir presença de toda a documentação e colas de estudo (fase0..fase12 + roteiros)
Get-ChildItem docs/estudo/fase*.md, docs/estudo/roteiro_estudo_completo.md, docs/DER_*, docs/modelagem_3fn.md, docs/decisoes.md, docs/roteiro_apresentacao.md, docs/guia_testes_por_fase.md, README.md | Select-Object Name, Length

# 6) Confirmar árvore limpa no git e que .env NÃO está versionado
git status --short
git ls-files .env
```

#### Saída esperada
- `reset.sh` termina com `==> reset concluido sem erros`.
- `test.sh` executa `tests/test_integridade.sql`, `tests/test_regras.sql` e `tests/test_seguranca.sql` e termina com `==> todos os testes passaram`.
- `python concorrencia/teste_concorrencia.py` termina com `TODOS OS TESTES DE CONCORRENCIA PASSARAM.` (exit code `0`).
- `python app/main.py --smoke-test` termina com `SMOKE TEST FASE 11 PASSOU.` (exit code `0`).
- Todos os documentos listados têm `Length > 0`.
- `git status --short` e `git ls-files .env` retornam vazios.
