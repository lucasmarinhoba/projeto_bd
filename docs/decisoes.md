# Decisões de projeto

Formato: **decisão** · alternativa considerada · por que esta.

## Fase 0 — Setup

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| Repositório montado no container em `/projeto` (somente leitura) | Enviar cada arquivo via `stdin` (`psql < arquivo`) | Permite `\i /projeto/...` no `psql` interativo e scripts únicos (`scripts/reset.sh`, `scripts/test.sh`) que funcionam igual com ou sem `make` (o Windows não tem `make` por padrão) |
| `reset` = `DROP SCHEMA reservas CASCADE` + recriação | `DROP DATABASE` + `CREATE DATABASE` | Não exige desconectar sessões abertas nem reconectar em outro banco; as configurações do banco (`timezone`, `search_path`) são reaplicadas pelo `00_setup.sql` |
| Roles criadas com `IF NOT EXISTS` em bloco `DO` | `DROP ROLE` + `CREATE ROLE` | Roles são globais ao cluster e sobrevivem ao reset do schema; dropar exigiria remover antes todas as dependências |
| `search_path = reservas, public` definido no banco | Prefixar `reservas.` em todo comando | Sessões interativas e revisões ficam mais simples; o `public` continua acessível para a extensão `btree_gist` |
| Dono dos objetos: `reservas_owner` (`NOLOGIN`, `NOSUPERUSER`) | Objetos de propriedade do `postgres` | Funções `SECURITY DEFINER` rodam com privilégios do dono; um dono sem superpoderes limita o dano de uma falha |
| Porta do host `5433` mapeada para `5432` do container (`POSTGRES_PORT=5433`) | Porta `5432` fixa no host | Evita conflito com instalação local do PostgreSQL ou outro container que já ocupe a porta `5432` na máquina de desenvolvimento |

## Fase 1 — Modelagem, DER e 3FN

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| Chaves primárias substitutas (`GENERATED ALWAYS AS IDENTITY`) mantendo `matricula`, `email` e `codigo` como `UNIQUE NOT NULL` | Chaves primárias naturais (`matricula`, `codigo`) | Chaves numéricas são menores nos índices e FKs (inclusive GiST) e ficam imunes a correções ou trocas de matrícula/código |
| Intervalo único `periodo tstzrange` com limites `[)` | Duas colunas `inicio timestamptz` e `fim timestamptz` | Permite `EXCLUDE USING gist (sala_id WITH =, periodo WITH &&)` direto sem índice funcional e evita falso conflito em horários adjacentes (`08–10` e `10–12`) |
| `status_reserva` apenas com `'ATIVA'` e `'CANCELADA'` (sem `'CONCLUIDA'`) | Incluir `'CONCLUIDA'` e rodar rotina periódica de atualização | Conclusão é um estado derivável do tempo (`upper(periodo) <= now()`); omiti-lo evita redundância e atualização em massa |
| Exclusão lógica (`ativo`/`ativa = false`) + `ON DELETE RESTRICT` em `usuario`, `sala`, `recurso` e `reserva` | `ON DELETE CASCADE` ou exclusão física | Preserva histórico de ocupação, relatórios mensais e trilha de auditoria em `log_reserva`; `CASCADE` fica restrito a `sala_recurso → sala` |
| Trilha `log_reserva` com snapshots `dados_antigos`/`dados_novos` em `jsonb` | Colunas normalizadas por campo auditado | Desnormalização *append-only* intencional: congela o estado completo da tupla no instante do evento e resiste a futuras mudanças de schema |

## Fase 2 — DDL e integridade declarativa

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| Uso explícito de `SET ROLE reservas_owner` nos scripts `01_tipos.sql` e `02_tabelas.sql` | Executar tudo como `postgres` e alterar dono depois | Garante que todos os tipos, domínios, tabelas e sequências nasçam com dono `reservas_owner` (`NOSUPERUSER`) sem comandos manuais de `ALTER OWNER` |
| `DOMAIN qtd_positiva` e `DOMAIN email_t` | `CHECK` repetido em cada coluna | Centraliza a definição da regra (`VALUE > 0` e regex de e-mail) e garante uniformidade entre `sala`, `sala_recurso` e `reserva` |
| Constraint `ck_periodo_valido` exigindo `lower_inc(periodo) AND NOT upper_inc(periodo)` | Aceitar qualquer tipo de limite (`[]`, `()`, `(]`) | Força no nível do DDL que toda inserção (mesmo manual fora das functions) normalize o intervalo para `[)` |

## Fase 3 — Seed base

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| Usuários de demonstração fixos nos IDs `1..4` e sala de demonstração no ID `5` (`A-105`) | Selecionar IDs aleatórios a cada demonstração | Permite roteiros reproduzíveis para as Fases 4, 9 e 11 e permite que a carga futura (Fase 6) isole esses IDs para não gerar falso bloqueio (RS008/RS010) |
| Separação entre `06_seed_base.sql` (cadastros) e `07_seed_massa.sql` (reservas) | Um único arquivo de seed | Permite testar triggers, functions e views antes da carga massiva sem sujar as tabelas com milhares de linhas prematuramente |
| Nomes gerados com `setseed(0.42)` + `random()` e matrículas/e-mails sequenciais (`idx`) | Gerar e-mails derivados do nome | Mantém a aleatoriedade reproduzível dos nomes sem risco de violar `UNIQUE` em homônimos |

## Fase 4 — Triggers e functions

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| `criar_reserva` e `cancelar_reserva` como `FUNCTION` (não `PROCEDURE`) | `PROCEDURE` com `COMMIT` interno e `CALL` | Functions retornam `id` direto em `SELECT criar_reserva(...)` e preservam atomicidade dentro da transação do chamador; o bloco `EXCEPTION` usa savepoint implícito para traduzir `23P01` em `RS010` |
| Regras de negócio em trigger `BEFORE` + `SECURITY DEFINER` apenas nas functions/auditoria | Validar capacidade/duração só dentro de `criar_reserva` | Defesa em profundidade: mesmo `INSERT`/`UPDATE` diretos ou cargas em massa respeitam todas as regras (capacidade, horário, duração, limite futuro) |
| Lock `FOR NO KEY UPDATE` na linha de `usuario` para o limite de 3 futuras | `SELECT FOR UPDATE` ou `SERIALIZABLE` | Serializa reservas concorrentes do mesmo usuário sem bloquear checagens de chave estrangeira (`FOR KEY SHARE`) e sem exigir `SERIALIZABLE` |
| `taxa_ocupacao` marcada como `STABLE SECURITY DEFINER` com `p_mes::timestamp` | `VOLATILE` sem `SECURITY DEFINER` | `STABLE` informa ao planner que o valor é constante no mesmo comando; `SECURITY DEFINER` permite que `app_reservas` execute a função sem ler `reserva`; `p_mes::timestamp` evita deslocamento de fuso no `date_trunc` |

## Fase 5 — Views e materialized view

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| `mv_ocupacao_mensal` atualizada via `REFRESH MATERIALIZED VIEW CONCURRENTLY` (sem trigger por linha) | Trigger `AFTER` em `reserva` dando `REFRESH` a cada inserção | Recalcular a matview a cada reserva tornaria escritas lentas e criaria contenção sob concorrência; `REFRESH CONCURRENTLY` (manual ou via `pg_cron`) não bloqueia leituras |
| Grade de meses em `mv_ocupacao_mensal` via `CROSS JOIN` (últimos 12 meses + meses futuros presentes em `reserva`) | `GROUP BY` direto apenas sobre linhas existentes em `reserva` | Garante que salas com `0` reservas em determinado mês também apareçam no relatório mensal com `taxa_ocupacao_pct = 0.00` |
| View auxiliar opcional `v_salas_recursos` | Permitir que a CLI faça `SELECT` direto na tabela `sala` | Mantém o princípio do menor privilégio (`app_reservas` não acessa nenhuma tabela diretamente) e facilita a escolha de `sala_id` na CLI |

## Fase 6 — Carga massiva

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| Manter `trg_regras_reserva`, `trg_audit_reserva` e `sem_conflito` **ativos** durante toda a carga | Usar `DISABLE TRIGGER ALL` para carregar mais rápido | A carga leva apenas ~1 segundo com os triggers ativos e comprova que todas as > 12.000 linhas obedecem às regras de negócio e geram auditoria |
| Calibrar `r_sel < 0.25` sobre `51.100` slots disjuntos (≈ 12.700 históricas + 120 futuras) | `r_sel < 0.22` | Garante folga confortável acima do requisito de 10.000 reservas mesmo após ~8% de cancelamentos (que permanecem na tabela como `CANCELADA`) |
| Excluir sala `5` e usuários `1..4` das reservas futuras do seed massivo | Incluir todos os cadastros na carga futura | Mantém os usuários e a sala de demonstração com contagem limpa no futuro para as demonstrações de concorrência (Fase 9) e CLI (Fase 11) |

## Fase 7 — Consultas analíticas

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| Q2 e Q4 consultam diretamente `sala` + `reserva` em vez de ler `mv_ocupacao_mensal` | Ler os dados já agregados direto da matview | Exercita `JOIN`, `HAVING` com subconsulta e funções de janela sobre os dados reais e permite validar a coerência numérica contra `mv_ocupacao_mensal` |
| Subconsulta do `HAVING` em Q2 usa `LEFT JOIN` sobre todas as salas | `AVG` apenas entre salas com reserva | Evita viés caso alguma sala tenha 0 reservas no mês analisado |
| Q4 calcula janela nos últimos 3 meses fechados e filtra o último mês no `SELECT` externo | Filtrar o mês antes do `LAG()` | Se filtrássemos o mês no `WHERE` antes da janela, o `LAG()` não enxergaria o mês anterior e retornaria sempre `NULL` |

## Fase 8 — Índices e `EXPLAIN ANALYZE`

| Decisão | Alternativa considerada | Por que esta |
|---|---|---|
| `idx_reserva_usuario_futuras` parcial (`WHERE status = 'ATIVA'`) sobre `(usuario_id, lower(periodo))` | Índice não parcial em `(usuario_id)` | Cobre as 3 colunas filtradas no trigger `fn_regras_reserva` (`usuario_id`, `status = 'ATIVA'` e `lower(periodo) > now()`), reduz espaço em disco e viabiliza `Index Only Scan` |
| `idx_reserva_inicio` B-tree parcial sobre `(lower(periodo)) WHERE status = 'ATIVA'` | Índice GiST em `(periodo)` sem `WHERE` | Consultas de intervalo por início (`lower(periodo) >= ... AND < ...`) com ordenação `ORDER BY lower(periodo)` aproveitam diretamente a ordenação nativa da B-tree sem `Sort` adicional |
| Medir com 3 execuções consecutivas (`VACUUM ANALYZE` antes de medir) mantendo `13.013` reservas | Criar banco `reservas_bench` de 500 mil linhas | Com `13.013` linhas as duas consultas escolhidas já têm seletividade suficiente (~0,01% e ~1,8%) para o otimizador trocar `Seq Scan` por `Index Only Scan`/`Index Scan`/`Bitmap Index Scan` sem necessidade de massa artificial extra |








