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

