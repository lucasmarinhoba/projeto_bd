#!/bin/sh
# scripts/test.sh — executado DENTRO do container:
#   docker compose exec -T db sh /projeto/scripts/test.sh       (ou: make test)
# Roda tests/test_*.sql em ordem. test_seguranca.sql roda como a role da aplicacao.
set -eu

ADMIN="psql -X -v ON_ERROR_STOP=1 -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
APP="psql -X -v ON_ERROR_STOP=1 -U ${APP_DB_USER} -d ${POSTGRES_DB}"

found=0
for f in /projeto/tests/test_*.sql; do
  [ -e "$f" ] || continue
  found=1
  echo "==> ${f#/projeto/}"
  case "$f" in
    */test_seguranca.sql) $APP -f "$f" ;;
    *)                    $ADMIN -f "$f" ;;
  esac
done

if [ "$found" -eq 0 ]; then
  echo "(nenhum arquivo em tests/ ainda)"
else
  echo "==> todos os testes passaram"
fi
