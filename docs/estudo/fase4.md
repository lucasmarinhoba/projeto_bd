# Cola de estudo — Fase 4 (Triggers e Functions)

- **`BEFORE` vs `AFTER`:** `trg_regras_reserva` é `BEFORE` para validar/barrar a linha antes de gravar; `trg_audit_reserva` é `AFTER` porque precisa do `id` já gerado (FK em `log_reserva`) e só deve auditar operações efetivadas.
- **`RETURN NEW` vs `RETURN NULL`:** em trigger `BEFORE FOR EACH ROW`, retornar `NULL` cancela silenciosamente a operação; em `AFTER`, o retorno é ignorado.
- **`OLD`, `NEW` e `TG_OP`:** distinguem `INSERT` (só `NEW`) de `UPDATE` (`OLD` e `NEW`), permitindo detectar a transição `ATIVA -> CANCELADA` como `CANCELAMENTO`.
- **`SECURITY DEFINER` + `SET search_path`:** a função roda com privilégios do dono (`reservas_owner`) para que `app_reservas` possa inserir/atualizar sem ter permissão nas tabelas; fixar `search_path = reservas, pg_temp` impede *search_path hijacking*.
- **Function vs Procedure + Subtransação:** `criar_reserva` é `FUNCTION` para retornar o `id` e participar da transação do chamador; o bloco `EXCEPTION` cria um savepoint implícito e desfaz o trabalho interno no erro (`RS010`).
- **`session_user` vs `current_user`:** dentro de `SECURITY DEFINER`, `current_user` muda para `reservas_owner`, enquanto `session_user` preserva quem abriu a conexão (`log_reserva.usuario_db`).
