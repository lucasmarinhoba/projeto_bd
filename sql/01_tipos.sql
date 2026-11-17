-- sql/01_tipos.sql
-- Tipos customizados (ENUMs e DOMAINs) do esquema reservas.

SET search_path = reservas, public;
SET ROLE reservas_owner;

CREATE TYPE status_reserva AS ENUM ('ATIVA', 'CANCELADA');
COMMENT ON TYPE status_reserva IS
  'Estados possiveis da reserva; CONCLUIDA nao e armazenada por ser derivavel de upper(periodo) <= now().';

CREATE TYPE tipo_usuario AS ENUM ('ALUNO', 'PROFESSOR', 'ADMIN');
COMMENT ON TYPE tipo_usuario IS
  'Perfil do usuario; apenas o dono da reserva ou ADMIN podem cancelar.';

CREATE TYPE tipo_sala AS ENUM ('SALA', 'LABORATORIO');
COMMENT ON TYPE tipo_sala IS
  'Classificacao do espaco fisico reservavel.';

CREATE DOMAIN email_t AS text
  CHECK (VALUE ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
COMMENT ON DOMAIN email_t IS
  'Endereco de e-mail validado declarativamente por expressao regular.';

CREATE DOMAIN qtd_positiva AS integer
  CHECK (VALUE > 0);
COMMENT ON DOMAIN qtd_positiva IS
  'Inteiro estritamente positivo reutilizado em capacidade, quantidade de recursos e participantes.';

RESET ROLE;
