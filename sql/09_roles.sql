-- sql/09_roles.sql
-- Configuracao de seguranca (principio do menor privilegio) para a role app_reservas.
-- A senha vem do .env via variavel psql (-v app_password=...), nunca fixa no repositorio.

SELECT set_config('reservas.app_password', :'app_password', false);

DO $$
DECLARE
  v_pwd text := current_setting('reservas.app_password');
BEGIN
  -- Roles pertencem ao cluster e sobrevivem ao reset do schema; criacao/atualizacao idempotente.
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_reservas') THEN
    EXECUTE format(
      'CREATE ROLE app_reservas LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
      v_pwd
    );
  ELSE
    EXECUTE format(
      'ALTER ROLE app_reservas WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
      v_pwd
    );
  END IF;

  EXECUTE format('GRANT CONNECT ON DATABASE %I TO app_reservas', current_database());
END
$$;

-- Garante que toda sessao da aplicacao use o schema e o fuso horario corretos.
ALTER ROLE app_reservas SET search_path = reservas, public;
ALTER ROLE app_reservas SET timezone = 'America/Fortaleza';

SET search_path = reservas, public;
SET ROLE reservas_owner;

-- Bloqueia acesso direto ao schema, tabelas, sequencias e funcoes internas.
REVOKE ALL ON SCHEMA reservas FROM PUBLIC, app_reservas;
GRANT  USAGE ON SCHEMA reservas TO app_reservas;

REVOKE ALL ON ALL TABLES IN SCHEMA reservas FROM PUBLIC, app_reservas;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA reservas FROM PUBLIC, app_reservas;
-- No PostgreSQL, EXECUTE em funcoes nasce concedido a PUBLIC; revogar explicitamente.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA reservas FROM PUBLIC, app_reservas;

-- Concede apenas leitura nas views/matview e execucao na API de negocio.
GRANT SELECT ON
  v_agenda_dia,
  v_reservas_usuario,
  mv_ocupacao_mensal,
  v_salas_recursos
TO app_reservas;

GRANT EXECUTE ON FUNCTION
  criar_reserva(bigint, integer, timestamptz, timestamptz, integer, text),
  cancelar_reserva(bigint, bigint, text),
  taxa_ocupacao(integer, date)
TO app_reservas;

RESET ROLE;
