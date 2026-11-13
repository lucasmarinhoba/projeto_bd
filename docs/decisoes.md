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
