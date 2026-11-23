-- sql/08_indices.sql
-- Indices secundarios para consultas fora do alcance do EXCLUDE sem_conflito.

SET search_path = reservas, public;
SET ROLE reservas_owner;

-- Indice 1: acelera a contagem de reservas futuras ativas por usuario no trigger
-- fn_regras_reserva (RS008) e consultas filtradas por usuario_id em v_reservas_usuario.
CREATE INDEX idx_reserva_usuario_futuras
  ON reserva (usuario_id, (lower(periodo)))
  WHERE status = 'ATIVA';

COMMENT ON INDEX idx_reserva_usuario_futuras IS
  'Indice parcial e funcional que atende a checagem de limite futuro (RS008) e buscas por usuario ativo.';

-- Indice 2: acelera buscas por janela de inicio sem filtro por sala_id
-- (que nao conseguem usar o indice GiST sem_conflito por ter sala_id como coluna lider).
CREATE INDEX idx_reserva_inicio
  ON reserva ((lower(periodo)))
  WHERE status = 'ATIVA';

COMMENT ON INDEX idx_reserva_inicio IS
  'Indice B-tree parcial sobre lower(periodo) para recortes temporais globais sem filtro por sala.';

ANALYZE reserva;

RESET ROLE;
