# DER Lógico — Sistema de Reserva de Salas e Laboratórios

Este diagrama lógico corresponde **1:1** ao esquema implementado em [`sql/01_tipos.sql`](../sql/01_tipos.sql) e [`sql/02_tabelas.sql`](../sql/02_tabelas.sql) no schema `reservas`.

```mermaid
erDiagram
    USUARIO {
        bigint id PK "GENERATED ALWAYS AS IDENTITY"
        text matricula UK "NOT NULL"
        text nome "NOT NULL, CHECK (length(trim(nome)) > 0)"
        email_t email UK "NOT NULL (DOMAIN text)"
        tipo_usuario tipo "NOT NULL (ENUM)"
        boolean ativo "NOT NULL DEFAULT true"
        timestamptz criado_em "NOT NULL DEFAULT now()"
    }

    SALA {
        integer id PK "GENERATED ALWAYS AS IDENTITY"
        text codigo UK "NOT NULL"
        text nome "NOT NULL"
        tipo_sala tipo "NOT NULL (ENUM)"
        qtd_positiva capacidade "NOT NULL (DOMAIN integer > 0)"
        boolean ativa "NOT NULL DEFAULT true"
    }

    RECURSO {
        integer id PK "GENERATED ALWAYS AS IDENTITY"
        text nome UK "NOT NULL"
    }

    SALA_RECURSO {
        integer sala_id PK,FK "REFERENCES sala(id) ON DELETE CASCADE"
        integer recurso_id PK,FK "REFERENCES recurso(id) ON DELETE RESTRICT"
        qtd_positiva quantidade "NOT NULL DEFAULT 1"
    }

    RESERVA {
        bigint id PK "GENERATED ALWAYS AS IDENTITY"
        bigint usuario_id FK "NOT NULL REFERENCES usuario(id) ON DELETE RESTRICT"
        integer sala_id FK "NOT NULL REFERENCES sala(id) ON DELETE RESTRICT"
        tstzrange periodo "NOT NULL, intervalo [) valido"
        qtd_positiva qtd_participantes "NOT NULL (DOMAIN integer > 0)"
        text finalidade "NULL permitido"
        status_reserva status "NOT NULL DEFAULT 'ATIVA' (ENUM)"
        timestamptz criada_em "NOT NULL DEFAULT now()"
        timestamptz cancelada_em "NULL <=> status = 'ATIVA'"
        text motivo_cancelamento "NULL permitido"
    }

    LOG_RESERVA {
        bigint id PK "GENERATED ALWAYS AS IDENTITY"
        bigint reserva_id FK "NOT NULL REFERENCES reserva(id) ON DELETE RESTRICT"
        text operacao "NOT NULL CHECK IN ('INSERT','UPDATE','CANCELAMENTO')"
        jsonb dados_antigos "NULL em INSERT"
        jsonb dados_novos "Snapshot NEW"
        text usuario_db "NOT NULL DEFAULT session_user"
        timestamptz data_hora "NOT NULL DEFAULT now()"
    }

    USUARIO ||--o{ RESERVA : "faz (1:N)"
    SALA ||--o{ RESERVA : "recebe (1:N)"
    SALA ||--o{ SALA_RECURSO : "possui (1:N)"
    RECURSO ||--o{ SALA_RECURSO : "equipa (1:N)"
    RESERVA ||--|{ LOG_RESERVA : "gera (1:N)"
```

---

## Tipos Customizados (`01_tipos.sql`)

| Tipo | Categoria | Definição / Valores | Uso nas tabelas |
|---|---|---|---|
| `status_reserva` | `ENUM` | `'ATIVA'`, `'CANCELADA'` | `reserva.status` |
| `tipo_usuario` | `ENUM` | `'ALUNO'`, `'PROFESSOR'`, `'ADMIN'` | `usuario.tipo` |
| `tipo_sala` | `ENUM` | `'SALA'`, `'LABORATORIO'` | `sala.tipo` |
| `email_t` | `DOMAIN` (`text`) | `CHECK (VALUE ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')` | `usuario.email` |
| `qtd_positiva` | `DOMAIN` (`integer`) | `CHECK (VALUE > 0)` | `sala.capacidade`, `sala_recurso.quantidade`, `reserva.qtd_participantes` |

---

## Constraints Declarativas por Tabela (`02_tabelas.sql`)

| Tabela | Tipo | Nome / Expressão | Regra garantida |
|---|---|---|---|
| `usuario` | `PK` | `id` | Identidade substituta imutável |
| `usuario` | `UNIQUE` | `matricula`, `email` | Chaves candidatas únicas |
| `usuario` | `CHECK` | `length(trim(nome)) > 0` | Impede nome vazio ou só com espaços |
| `sala` | `PK` / `UNIQUE` | `id` / `codigo` | Identidade substituta e código único |
| `recurso` | `PK` / `UNIQUE` | `id` / `nome` | Identidade substituta e nome único |
| `sala_recurso` | `PK` / `FK` | `(sala_id, recurso_id)` | Relação N:N sem duplicata de recurso na mesma sala |
| `reserva` | `PK` / `FK` | `id` / `usuario_id`, `sala_id` | Integridade referencial com `ON DELETE RESTRICT` |
| `reserva` | `CHECK` | `ck_periodo_valido` | `NOT isempty(periodo) AND NOT lower_inf(periodo) AND NOT upper_inf(periodo) AND lower_inc(periodo) AND NOT upper_inc(periodo)` |
| `reserva` | `CHECK` | `ck_cancelamento_coerente` | `(status = 'CANCELADA') = (cancelada_em IS NOT NULL)` |
| `reserva` | `EXCLUDE` | `sem_conflito` | `EXCLUDE USING gist (sala_id WITH =, periodo WITH &&) WHERE (status = 'ATIVA')` — bloqueia sobreposição na mesma sala via `btree_gist` |
| `log_reserva` | `PK` / `FK` | `id` / `reserva_id` | Trilha append-only (`ON DELETE RESTRICT`) |
| `log_reserva` | `CHECK` | `operacao` | `operacao IN ('INSERT', 'UPDATE', 'CANCELAMENTO')` |
