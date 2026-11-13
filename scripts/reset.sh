#!/bin/sh
# scripts/reset.sh — executado DENTRO do container:
#   docker compose exec -T db sh /projeto/scripts/reset.sh      (ou: make reset)
# Recria o schema do zero: 99_reset.sql primeiro, depois sql/0*.sql em ordem.
set -eu

PSQL="psql -X -q -v ON_ERROR_STOP=1 -U ${POSTGRES_USER} -d ${POSTGRES_DB}"

echo "==> sql/99_reset.sql"
$PSQL -f /projeto/sql/99_reset.sql

for f in /projeto/sql/0*.sql; do
  echo "==> ${f#/projeto/}"
  # app_password fica disponivel como variavel psql (:'app_password') para o 09_roles.sql
  $PSQL -v app_password="${APP_DB_PASSWORD}" -f "$f"
done

echo "==> reset concluido sem erros"
