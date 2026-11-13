-- sql/00_setup.sql
-- Configuracao inicial do banco: role dona, schema, extensao e fuso horario.

-- Role dona dos objetos: NAO e superusuario (principio do menor privilegio).
-- Roles pertencem ao cluster e sobrevivem ao reset do schema; por isso a criacao e condicional.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'reservas_owner') THEN
    CREATE ROLE reservas_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;
END
$$;

-- Schema dedicado para isolar os objetos do projeto do schema public.
CREATE SCHEMA reservas AUTHORIZATION reservas_owner;

-- btree_gist permite combinar igualdade (=) de tipos escalares (sala_id)
-- com sobreposicao (&&) de ranges (tstzrange) no mesmo indice GiST do EXCLUDE.
CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA public;

-- Fixa fuso horario e search_path padrao do banco (valem para toda nova sessao).
-- search_path no banco evita prefixar "reservas." nas sessoes interativas e nas revisoes.
DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I SET timezone = %L', current_database(), 'America/Fortaleza');
  EXECUTE format('ALTER DATABASE %I SET search_path = reservas, public', current_database());
END
$$;

SET search_path = reservas, public;
SET timezone = 'America/Fortaleza';
