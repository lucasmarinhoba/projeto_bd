# Cola de estudo — Fase 10 (Segurança e role `app_reservas`)

- **Princípio do menor privilégio:** `app_reservas` não é superusuário, não pode criar tabelas (`USAGE` sem `CREATE`) e não tem nenhum privilégio nas 6 tabelas base; só lê as views e executa as 3 functions da API.
- **Por que `REVOKE EXECUTE ... FROM PUBLIC`:** no PostgreSQL, toda função recém-criada recebe `EXECUTE` para `PUBLIC` automaticamente; sem o `REVOKE`, qualquer usuário do cluster poderia invocá-la.
- **Como `criar_reserva` e as views funcionam sem acesso às tabelas:** as functions são `SECURITY DEFINER` (rodam como `reservas_owner`, dona das tabelas) e as views executam por padrão com os privilégios do dono (`security_invoker` desligado).
- **Prevenção a *search_path hijacking*:** todas as functions `SECURITY DEFINER` fixam `SET search_path = reservas, pg_temp` e pertencem a `reservas_owner` (`NOSUPERUSER`).
- **`session_user` vs `current_user` + limitação:** `log_reserva` grava `session_user` (`app_reservas`), não o dono. Limitação assumida: a aplicação informa o `usuario_id`; evolução natural é **Row-Level Security (RLS)** com `SET LOCAL app.usuario_id`.
