# Cola de estudo — Fase 11 (Aplicação CLI e Página Web)

- **Por que a aplicação não valida regras:** toda regra (conflito, capacidade, duração, horário, limite futuro, permissão de cancelamento) vive no PostgreSQL; se a duração máxima mudar de 4 h para 3 h, **zero linha** da aplicação muda.
- **SQL injection e queries parametrizadas:** todas as consultas usam marcadores `%s` com tupla de parâmetros (`cur.execute(sql, params)`), nunca f-strings ou concatenação.
- **`autocommit` vs transação implícita no psycopg 3:** com `autocommit=False`, todo comando abre transação implícita; por isso `executar_sql` chama `conn.commit()` no sucesso (para persistir `criar_reserva`/`cancelar_reserva`) e `conn.rollback()` no erro.
- **Repasse limpo de erros:** `psycopg.Error` captura SQLSTATEs customizados (`RS001`–`RS014`) e exibe exatamente `e.diag.message_primary` vinda do banco.
- **CLI + Web mínima sobre o mesmo `db.py`:** ambas conectam exclusivamente como `app_reservas` e expõem só as 4 funcionalidades pedidas no enunciado.
