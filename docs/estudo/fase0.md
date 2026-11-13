# Cola de estudo — Fase 0 (Setup)

- **`btree_gist`:** o índice GiST sabe trabalhar com ranges (`tstzrange` + operador `&&`), mas não tem classe de operador padrão para igualdade (`=`) de inteiros (`sala_id`). A extensão `btree_gist` adiciona suporte a `=` de tipos escalares dentro do GiST, viabilizando o `EXCLUDE USING gist (sala_id WITH =, periodo WITH &&)`.
- **Dono `NOSUPERUSER` (`reservas_owner`):** funções `SECURITY DEFINER` e views rodam com os privilégios do seu dono. Se o dono fosse superusuário, qualquer falha nessas funções daria acesso total ao cluster; usando uma role sem privilégios administrativos, o risco fica contido ao schema `reservas`.
- **Idempotência do `reset`:** `sql/99_reset.sql` (`DROP SCHEMA ... CASCADE`) roda **antes** dos scripts `0*.sql`, e roles são criadas com `IF NOT EXISTS` porque pertencem ao cluster e sobrevivem ao `DROP SCHEMA`.
- **Timezone fixo (`America/Fortaleza`):** garante que conversões de `timestamptz` para horário local nas regras de funcionamento (07:00–22:00) e views sejam consistentes.
