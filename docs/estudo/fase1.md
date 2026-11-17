# Cola de estudo — Fase 1 (Modelagem, DER e 3FN)

- **1FN / 2FN / 3FN:** **1FN** = valores atômicos (recursos saíram de `sala` para `sala_recurso`); **2FN** = sem dependência parcial (`sala_recurso.quantidade` depende do par `(sala_id, recurso_id)` inteiro); **3FN** = sem dependência transitiva (`reserva` guarda `usuario_id`/`sala_id`, nunca `nome` ou `capacidade`).
- **Atributos derivados omitidos:** `CONCLUIDA` não está em `status_reserva` porque deriva de `status = 'ATIVA' AND upper(periodo) <= now()`; `duracao` deriva de `upper(periodo) - lower(periodo)`.
- **`tstzrange` com `[)`:** é tipo escalar no PG (respeita a 1FN), simplifica o `EXCLUDE` com `&&` e garante que reservas adjacentes (`08–10` e `10–12`) não conflitem.
- **`log_reserva` (`jsonb`):** desnormalização intencional *append-only* para congelar o snapshot do momento da operação, imune a alterações futuras.
- **`ON DELETE`:** `RESTRICT` em `reserva` e `log_reserva` preserva histórico (desativa-se com `ativo`/`ativa = false`); `CASCADE` em `sala_recurso → sala` apaga o vínculo associativo.
