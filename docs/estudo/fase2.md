# Cola de estudo — Fase 2 (DDL e integridade declarativa)

- **`EXCLUDE USING gist (sala_id WITH =, periodo WITH &&)`:** cria um índice GiST; a cada `INSERT`/`UPDATE`, o banco verifica atomicamente se existe linha ativa com igual `sala_id` e `periodo` sobreposto (`&&`), lançando SQLSTATE `23P01` (`exclusion_violation`).
- **Papel da `btree_gist`:** índices GiST nativos não possuem operador de igualdade (`=`) para tipos escalares como `integer`; `btree_gist` fornece essa classe de operador para combinar `sala_id WITH =` com `periodo WITH &&`.
- **Por que `WHERE (status = 'ATIVA')`:** torna o índice **parcial**, permitindo que reservas canceladas liberem o horário para novas reservas sem apagar o histórico.
- **Por que intervalo `[)`:** meio-aberto (início inclusivo, fim exclusivo) impede falso conflito entre `08:00–10:00` e `10:00–12:00`.
- **ENUM × DOMAIN × tabela de domínio:** `ENUM` define conjunto pequeno e estável de rótulos (`status_reserva`); `DOMAIN` reutiliza regras de validação entre várias colunas (`qtd_positiva`, `email_t`); tabela de domínio dá mais flexibilidade via `FK`, ao custo de `JOIN`.
