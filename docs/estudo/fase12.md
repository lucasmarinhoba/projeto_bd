# Cola de estudo — Fase 12 (Documentação, Ensaio e Entrega)

- **Entrega reproduzível:** qualquer máquina com Docker e Python sobe o sistema inteiro a partir do zero com `scripts/reset.sh` + `scripts/test.sh` (ou `make reset && make test`), sem ajustes manuais nem edição de arquivos versionados.
- **Congelamento com tag `entrega`:** marca o commit exato avaliado e permite auditoria histórica fase a fase via `git checkout <hash>` descrito em `docs/guia_testes_por_fase.md`.
- **Segredos fora do Git:** `.env` nunca é versionado (`git ls-files .env` retorna vazio); apenas `.env.example` documenta as chaves necessárias.
- **Preparo para a arguição oral individual:** dominar as justificativas em `docs/decisoes.md` e executar ao vivo no `psql` as demos `H2` (conflito `23P01`), `H9` (duas sessões concorrentes) e alteração dinâmica da duração máxima em `fn_regras_reserva`.
