-- sql/99_reset.sql
-- Remove o schema da aplicacao para recriacao limpa e idempotente.
-- Deve ser executado ANTES dos scripts sql/0*.sql no `make reset`.

DROP SCHEMA IF EXISTS reservas CASCADE;
