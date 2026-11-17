-- sql/02_tabelas.sql
-- DDL das 6 tabelas e suas constraints declarativas de integridade.

SET search_path = reservas, public;
SET ROLE reservas_owner;

-- 1. Usuarios da instituicao
CREATE TABLE usuario (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  matricula  text         NOT NULL UNIQUE,
  nome       text         NOT NULL CHECK (length(trim(nome)) > 0),
  email      email_t      NOT NULL UNIQUE,
  tipo       tipo_usuario NOT NULL,
  ativo      boolean      NOT NULL DEFAULT true,
  criado_em  timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE usuario IS
  'Usuarios que solicitam ou administram reservas; desativados via ativo=false (nunca apagados com reservas).';

-- 2. Salas e laboratorios
CREATE TABLE sala (
  id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo      text         NOT NULL UNIQUE,
  nome        text         NOT NULL CHECK (length(trim(nome)) > 0),
  tipo        tipo_sala    NOT NULL,
  capacidade  qtd_positiva NOT NULL,
  ativa       boolean      NOT NULL DEFAULT true
);
COMMENT ON TABLE sala IS
  'Salas de aula e laboratorios disponiveis para reserva; desativacao logica via ativa=false.';

-- 3. Catalogo de recursos fisicos
CREATE TABLE recurso (
  id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nome  text NOT NULL UNIQUE CHECK (length(trim(nome)) > 0)
);
COMMENT ON TABLE recurso IS
  'Catalogo normalizado de equipamentos/recursos instalaveis nas salas.';

-- 4. Associacao N:N entre sala e recurso
CREATE TABLE sala_recurso (
  sala_id     integer      NOT NULL REFERENCES sala(id)    ON DELETE CASCADE,
  recurso_id  integer      NOT NULL REFERENCES recurso(id) ON DELETE RESTRICT,
  quantidade  qtd_positiva NOT NULL DEFAULT 1,
  PRIMARY KEY (sala_id, recurso_id)
);
COMMENT ON TABLE sala_recurso IS
  'Inventario de recursos por sala; quantidade depende da chave composta inteira (2FN/3FN).';

-- 5. Reservas de salas
CREATE TABLE reserva (
  id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id           bigint         NOT NULL REFERENCES usuario(id) ON DELETE RESTRICT,
  sala_id              integer        NOT NULL REFERENCES sala(id)    ON DELETE RESTRICT,
  periodo              tstzrange      NOT NULL,
  qtd_participantes    qtd_positiva   NOT NULL,
  finalidade           text,
  status               status_reserva NOT NULL DEFAULT 'ATIVA',
  criada_em            timestamptz    NOT NULL DEFAULT now(),
  cancelada_em         timestamptz,
  motivo_cancelamento  text,

  CONSTRAINT ck_periodo_valido CHECK (
        NOT isempty(periodo)
    AND NOT lower_inf(periodo)
    AND NOT upper_inf(periodo)
    AND lower_inc(periodo)
    AND NOT upper_inc(periodo)
  ),
  CONSTRAINT ck_cancelamento_coerente CHECK (
    (status = 'CANCELADA') = (cancelada_em IS NOT NULL)
  ),
  CONSTRAINT sem_conflito
    EXCLUDE USING gist (sala_id WITH =, periodo WITH &&)
    WHERE (status = 'ATIVA')
);
COMMENT ON TABLE reserva IS
  'Reservas de espacos; conflitos de horario sao impedidos atomicamente pela constraint sem_conflito.';
COMMENT ON COLUMN reserva.periodo IS
  'Intervalo meio-aberto [inicio, fim) com fuso horario; evita conflito entre reservas adjacentes.';
COMMENT ON CONSTRAINT ck_periodo_valido ON reserva IS
  'Impede intervalo vazio, infinito ou diferente do formato meio-aberto [).';
COMMENT ON CONSTRAINT ck_cancelamento_coerente ON reserva IS
  'Garante que toda reserva CANCELADA tenha cancelada_em preenchido e toda ATIVA tenha NULL.';
COMMENT ON CONSTRAINT sem_conflito ON reserva IS
  'Indice GiST parcial (btree_gist): impede sobreposicao de periodos ATIVOS na mesma sala (SQLSTATE 23P01).';

-- 6. Trilha de auditoria append-only
CREATE TABLE log_reserva (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reserva_id     bigint NOT NULL REFERENCES reserva(id) ON DELETE RESTRICT,
  operacao       text   NOT NULL CHECK (operacao IN ('INSERT', 'UPDATE', 'CANCELAMENTO')),
  dados_antigos  jsonb,
  dados_novos    jsonb,
  usuario_db     text        NOT NULL DEFAULT session_user,
  data_hora      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE log_reserva IS
  'Auditoria imutavel (append-only) com snapshot jsonb; desnormalizacao intencional para preservar historico.';
COMMENT ON COLUMN log_reserva.usuario_db IS
  'Registra session_user (login real da sessao), preservado mesmo quando alterado via SECURITY DEFINER.';

RESET ROLE;
