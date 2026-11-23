# Sistema de Reserva de Salas e Laboratórios (PostgreSQL 16 + Python)

Projeto de Banco de Dados baseado na arquitetura **"casca fina na aplicação + regras de negócio no PostgreSQL"**. Toda integridade referencial, controle de sobreposição de horários (`EXCLUDE USING gist`), triggers de negócio/auditoria, controle de concorrência, views analíticas e controle de acesso (`app_reservas`) vivem integralmente no PostgreSQL 16 em SQL puro (sem ORM).

---

## 1. Pré-requisitos

- **Docker Desktop** (com `docker compose` v2)
- **Python 3.10+** e biblioteca **`psycopg[binary]>=3.1`** (`pip install -r app/requirements.txt`)
- *(Opcional)* GNU `make` no Linux/macOS (no Windows PowerShell todos os alvos possuem comando equivalente direto via Docker abaixo)

---

## 2. Como subir e testar do zero

### Passo 1 — Configurar variáveis de ambiente (`.env`)

```powershell
# No Windows PowerShell:
Copy-Item .env.example .env

# No Linux/macOS:
# cp .env.example .env
```

> O arquivo `.env` está no `.gitignore`. Por padrão, a porta exposta no host é **`5433`** (`POSTGRES_PORT=5433` → `5432` no container `reservas_db`) para evitar conflito com PostgreSQL local.

### Passo 2 — Instalar dependência Python da aplicação

```powershell
pip install -r app/requirements.txt
```

### Passo 3 — Subir o banco, recriar tudo e rodar os testes

| Ação | Com `make` | Sem `make` (Windows PowerShell / Docker direto) |
|---|---|---|
| Subir container PostgreSQL 16 | `make up` | `docker compose up -d --wait` |
| Recriar schema, tabelas, seeds, views, índices e roles | `make reset` | `docker compose exec -T db sh /projeto/scripts/reset.sh` |
| Rodar suíte SQL completa (integridade, regras e segurança) | `make test` | `docker compose exec -T db sh /projeto/scripts/test.sh` |
| Abrir `psql` interativo | `make psql` | `docker compose exec db psql -U postgres -d reservas` |
| Abrir CLI interativa (`app_reservas`) | `make app` | `python app/main.py` |
| Abrir Página Web local (`http://127.0.0.1:8000`) | `make web` | `python app/main.py --web` |
| Rodar smoke test E2E (CLI + Web + erros RSxxx) | — | `python app/main.py --smoke-test` |
| Rodar teste de concorrência (20 threads × 10 baterias) | — | `python concorrencia/teste_concorrencia.py` |
| Derrubar container (preserva volume) | `make down` | `docker compose down` |

> **Observação:** rode `docker compose exec -T db sh /projeto/scripts/reset.sh` sempre que quiser restaurar o banco limpo (com os `13.013` registros de seed e os IDs de demonstração livres de reservas futuras).

---

## 3. Usuários e Sala de Demonstração (IDs Fixos)

O script [`sql/06_seed_base.sql`](sql/06_seed_base.sql) reserva os IDs iniciais abaixo para testes manuais, demonstrações de concorrência e uso na CLI/Página Web (a carga futura de `sql/07_seed_massa.sql` mantém esses IDs livres no futuro):

| Entidade | ID | Código / Matrícula | Nome / Descrição | Papel / Capacidade |
|---|---|---|---|---|
| `usuario` | **`1`** | `20260001` | Lucas Marinho (Demo Aluno 1) | `ALUNO` |
| `usuario` | **`2`** | `20260002` | Beatriz Costa (Demo Aluno 2) | `ALUNO` |
| `usuario` | **`3`** | `PROF0001` | Prof. Carlos Eduardo (Demo Professor) | `PROFESSOR` |
| `usuario` | **`4`** | `ADM0001` | Helena Souza (Demo Admin) | `ADMIN` |
| `sala` | **`5`** | `A-105` | Sala de Demonstracao A-105 | `SALA` (`40` lugares) |

Além dos 4 usuários e 1 sala de demonstração, a carga completa possui **20 salas** (`12 SALA` + `8 LABORATORIO`), **8 recursos**, **89 vínculos `sala_recurso`**, **150 usuários** e **13.013 reservas** (`11.984 ATIVA` + `1.029 CANCELADA`) auditadas por **14.042 registros** em `log_reserva`.

---

## 4. Funcionalidades da Aplicação (`app/`)

A aplicação conecta **exclusivamente** como a role restrita **`app_reservas`** (sem acesso direto a nenhuma tabela base) e não possui nenhuma regra de negócio no código Python — apenas parsing de formato de entrada e repasse das mensagens de erro `e.diag.message_primary` levantadas pelo banco:

1. **Agenda da sala no dia** → consulta `v_agenda_dia`
2. **Criar reserva** → chama `SELECT criar_reserva(...)`
3. **Cancelar reserva** → chama `SELECT cancelar_reserva(...)`
4. **Relatório de ocupação mensal** → consulta `mv_ocupacao_mensal`
5. *(Apoio na interface)* Listagem de salas e recursos via `v_salas_recursos`

Você pode usar tanto pelo terminal (**CLI** com `python app/main.py`) quanto pelo navegador (**Página Web local** com `python app/main.py --web` em `http://127.0.0.1:8000`).

---

## 5. Estrutura do Repositório

```text
projeto_bd/
├── README.md
├── docker-compose.yml               # PostgreSQL 16 (host 5433 -> container 5432)
├── Makefile                         # Atalhos up, down, reset, psql, test, app, web
├── .env.example                     # Variáveis de ambiente modelo
├── scripts/
│   ├── reset.sh                     # Executa 99_reset.sql e 00..09 em ordem
│   └── test.sh                      # Executa test_integridade, test_regras e test_seguranca
├── sql/
│   ├── 00_setup.sql                 # Schema, btree_gist, reservas_owner, timezone/search_path
│   ├── 01_tipos.sql                 # 3 ENUMs e 2 DOMAINs
│   ├── 02_tabelas.sql               # 6 tabelas, FKs ON DELETE, CHECKs e EXCLUDE sem_conflito
│   ├── 03_triggers.sql              # trg_audit_reserva (AFTER) e trg_regras_reserva (BEFORE)
│   ├── 04_functions.sql             # criar_reserva, cancelar_reserva, taxa_ocupacao
│   ├── 05_views.sql                 # v_agenda_dia, v_reservas_usuario, mv_ocupacao_mensal, v_salas_recursos
│   ├── 06_seed_base.sql             # 20 salas, 8 recursos, 89 sala_recurso, 150 usuários
│   ├── 07_seed_massa.sql            # 13.013 reservas e 14.042 logs com triggers ativos
│   ├── 08_indices.sql               # idx_reserva_usuario_futuras e idx_reserva_inicio
│   ├── 09_roles.sql                 # Role app_reservas e princípio do menor privilégio
│   └── 99_reset.sql                 # DROP SCHEMA reservas CASCADE
├── tests/
│   ├── test_integridade.sql         # Testes declarativos (Fase 2)
│   ├── test_regras.sql              # RS001..RS014 + auditoria + fluxo positivo (Fase 4)
│   └── test_seguranca.sql           # Executado como app_reservas (Fase 10)
├── analise/
│   ├── consultas_analiticas.sql     # 5 consultas analíticas (Q1..Q5)
│   ├── consultas_analiticas.md      # SQL, saída real e interpretação de Q1..Q5
│   └── explain/                     # Antes/depois (EXPLAIN ANALYZE, BUFFERS), prints e analise.md
├── concorrencia/
│   ├── roteiro.md                   # Evidências de pg_stat_activity e pg_locks
│   ├── sessao_A.sql / sessao_B.sql  # Scripts para reprodução em 3 terminais psql
│   └── teste_concorrencia.py        # 20 threads x 10 baterias + corrida do limite
├── app/
│   ├── db.py                        # Conexão app_reservas, SQL parametrizado, parsers
│   ├── main.py                      # CLI interativa + --web + --smoke-test
│   ├── web.py                       # Servidor HTTP local (stdlib http.server)
│   └── requirements.txt             # psycopg[binary]>=3.1
└── docs/
    ├── DER_conceitual.png           # Diagrama Entidade-Relacionamento conceitual
    ├── DER_logico.md                # Diagrama lógico em Mermaid
    ├── modelagem_3fn.md             # Justificativa de 1FN/2FN/3FN e tabela ON DELETE
    ├── decisoes.md                  # Decisões arquiteturais (alternativa e justificativa)
    ├── guia_testes_por_fase.md      # Comandos de teste de todas as fases + git checkout por fase
    ├── roteiro_apresentacao.md      # Cronograma da apresentação (20 min) e guia oral
    └── estudo/
        ├── roteiro_estudo_completo.md
        └── fase0.md .. fase12.md
```

---

## 6. Documentação e Guias de Estudo

- **Guia completo de testes fase a fase (com "viagem no tempo" via Git):** [`docs/guia_testes_por_fase.md`](docs/guia_testes_por_fase.md)
- **Modelagem e Normalização:** [`docs/DER_conceitual.png`](docs/DER_conceitual.png) · [`docs/DER_logico.md`](docs/DER_logico.md) · [`docs/modelagem_3fn.md`](docs/modelagem_3fn.md)
- **Decisões de Projeto:** [`docs/decisoes.md`](docs/decisoes.md)
- **Análise SQL e Índices (`EXPLAIN ANALYZE`):** [`analise/consultas_analiticas.md`](analise/consultas_analiticas.md) · [`analise/explain/analise.md`](analise/explain/analise.md)
- **Concorrência:** [`concorrencia/roteiro.md`](concorrencia/roteiro.md)
- **Apresentação e Estudo para Oral:** [`docs/roteiro_apresentacao.md`](docs/roteiro_apresentacao.md) · [`docs/estudo/roteiro_estudo_completo.md`](docs/estudo/roteiro_estudo_completo.md)
