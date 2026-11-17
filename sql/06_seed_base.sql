-- sql/06_seed_base.sql
-- Dados base deterministicos (salas, recursos, sala_recurso e usuarios) para testes e demonstracao.

SET search_path = reservas, public;
SET timezone = 'America/Fortaleza';

-- Garante geracao reproduzivel de valores pseudoaleatorios neste script.
SELECT setseed(0.42);

-- =============================================================================
-- 1. Salas e laboratorios (20 espacos: 12 SALA + 8 LABORATORIO)
-- A sala id = 5 (A-105) e reservada para demonstracoes manuais/concorrencia.
-- =============================================================================
INSERT INTO sala (codigo, nome, tipo, capacidade) VALUES
  ('A-101', 'Sala de Aula A-101',          'SALA',        30),
  ('A-102', 'Sala de Aula A-102',          'SALA',        40),
  ('A-103', 'Sala de Aula A-103',          'SALA',        50),
  ('A-104', 'Sala de Aula A-104',          'SALA',        60),
  ('A-105', 'Sala de Demonstracao A-105',  'SALA',        40), -- id = 5 (demo fixa)
  ('A-106', 'Sala de Aula A-106',          'SALA',        35),
  ('A-107', 'Sala de Aula A-107',          'SALA',        45),
  ('A-108', 'Sala de Seminarios A-108',    'SALA',        25),
  ('B-201', 'Sala de Aula B-201',          'SALA',        55),
  ('B-202', 'Anfiteatro B-202',            'SALA',        70),
  ('B-203', 'Auditorio B-203',             'SALA',        80),
  ('B-204', 'Sala de Estudos B-204',       'SALA',        30),
  ('LAB-01', 'Laboratorio de Redes',       'LABORATORIO', 20),
  ('LAB-02', 'Laboratorio de Hardware',    'LABORATORIO', 25),
  ('LAB-03', 'Laboratorio de Robotica',    'LABORATORIO', 30),
  ('LAB-04', 'Laboratorio de Banco Dados', 'LABORATORIO', 30),
  ('LAB-05', 'Laboratorio de Software I',  'LABORATORIO', 35),
  ('LAB-06', 'Laboratorio de Software II', 'LABORATORIO', 40),
  ('LAB-07', 'Laboratorio de Ciencia Dados','LABORATORIO',45),
  ('LAB-08', 'Laboratorio de IoT',         'LABORATORIO', 24);

-- =============================================================================
-- 2. Catalogo de recursos (8 recursos) e associacao N:N sala_recurso (>= 60 linhas)
-- =============================================================================
INSERT INTO recurso (nome) VALUES
  ('Projetor'),
  ('Quadro branco'),
  ('Ar-condicionado'),
  ('Computadores'),
  ('Lousa digital'),
  ('Bancadas'),
  ('Sistema de som'),
  ('Kit de robotica');

-- Infraestrutura basica em todas as 20 salas (20 x 3 = 60 linhas)
INSERT INTO sala_recurso (sala_id, recurso_id, quantidade)
SELECT s.id, r.id,
       CASE
         WHEN r.nome = 'Ar-condicionado' AND s.capacidade >= 50 THEN 2
         WHEN r.nome = 'Quadro branco'   AND s.capacidade >= 60 THEN 2
         ELSE 1
       END
FROM sala s
CROSS JOIN recurso r
WHERE r.nome IN ('Projetor', 'Quadro branco', 'Ar-condicionado');

-- Laboratorios recebem computadores (mesma quantidade da capacidade) e bancadas (+16 linhas)
INSERT INTO sala_recurso (sala_id, recurso_id, quantidade)
SELECT s.id, r.id,
       CASE
         WHEN r.nome = 'Computadores' THEN s.capacidade
         ELSE 6
       END
FROM sala s
JOIN recurso r ON r.nome IN ('Computadores', 'Bancadas')
WHERE s.tipo = 'LABORATORIO';

-- Salas maiores (>= 50 lugares) recebem sistema de som e lousa digital
INSERT INTO sala_recurso (sala_id, recurso_id, quantidade)
SELECT s.id, r.id, 1
FROM sala s
JOIN recurso r ON r.nome IN ('Sistema de som', 'Lousa digital')
WHERE s.capacidade >= 50;

-- Laboratorios selecionados recebem kits de robotica
INSERT INTO sala_recurso (sala_id, recurso_id, quantidade)
SELECT s.id, r.id, 10
FROM sala s
JOIN recurso r ON r.nome = 'Kit de robotica'
WHERE s.codigo IN ('LAB-03', 'LAB-06', 'LAB-08');

-- =============================================================================
-- 3. Usuarios de demonstracao fixos (IDs 1..4) + 146 gerados = 150 usuarios
--    Total: 120 ALUNO, 25 PROFESSOR, 5 ADMIN
-- =============================================================================
INSERT INTO usuario (matricula, nome, email, tipo) VALUES
  ('20260001', 'Lucas Marinho (Demo Aluno 1)',         'lucas.demo@inst.edu.br',   'ALUNO'),
  ('20260002', 'Beatriz Costa (Demo Aluno 2)',         'beatriz.demo@inst.edu.br', 'ALUNO'),
  ('PROF0001', 'Prof. Carlos Eduardo (Demo Professor)','carlos.prof@inst.edu.br',  'PROFESSOR'),
  ('ADM0001',  'Helena Souza (Demo Admin)',            'helena.admin@inst.edu.br', 'ADMIN');

WITH nomes AS (
  SELECT
    ARRAY[
      'Ana', 'Bruno', 'Camila', 'Daniel', 'Eduarda', 'Felipe', 'Gabriela', 'Henrique',
      'Isabela', 'Joao', 'Larissa', 'Mateus', 'Natalia', 'Pedro', 'Rafael', 'Sofia',
      'Thiago', 'Vitoria', 'Arthur', 'Mariana'
    ] AS prenomes,
    ARRAY[
      'Silva', 'Santos', 'Oliveira', 'Souza', 'Pereira', 'Costa', 'Rodrigues', 'Almeida',
      'Nascimento', 'Lima', 'Araujo', 'Fernandes', 'Carvalho', 'Gomes', 'Martins', 'Rocha',
      'Ribeiro', 'Alves'
    ] AS sobrenomes
),
serie AS (
  SELECT
    gs AS idx,
    1 + floor(random() * 20)::int AS i_nome,
    1 + floor(random() * 18)::int AS i_sob1,
    1 + floor(random() * 18)::int AS i_sob2
  FROM generate_series(1, 146) AS gs
)
INSERT INTO usuario (matricula, nome, email, tipo)
SELECT
  CASE
    WHEN s.idx <= 118 THEN '2026' || lpad((s.idx + 2)::text, 4, '0')
    WHEN s.idx <= 142 THEN 'PROF' || lpad((s.idx - 117)::text, 4, '0')
    ELSE                   'ADM'  || lpad((s.idx - 141)::text, 4, '0')
  END AS matricula,
  CASE
    WHEN s.idx BETWEEN 119 AND 142 THEN
      'Prof. ' || n.prenomes[s.i_nome] || ' ' || n.sobrenomes[s.i_sob1] || ' ' || n.sobrenomes[s.i_sob2]
    ELSE
      n.prenomes[s.i_nome] || ' ' || n.sobrenomes[s.i_sob1] || ' ' || n.sobrenomes[s.i_sob2]
  END AS nome,
  CASE
    WHEN s.idx <= 118 THEN 'aluno' || (s.idx + 2) || '@inst.edu.br'
    WHEN s.idx <= 142 THEN 'prof'  || (s.idx - 117) || '@inst.edu.br'
    ELSE                   'admin' || (s.idx - 141) || '@inst.edu.br'
  END AS email,
  CASE
    WHEN s.idx <= 118 THEN 'ALUNO'::tipo_usuario
    WHEN s.idx <= 142 THEN 'PROFESSOR'::tipo_usuario
    ELSE                   'ADMIN'::tipo_usuario
  END AS tipo
FROM serie s
CROSS JOIN nomes n
ORDER BY s.idx;
