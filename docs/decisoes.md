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



