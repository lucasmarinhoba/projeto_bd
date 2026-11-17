# Cola de estudo — Fase 3 (Seed base)

- **`setseed(0.42)` + `random()`:** define a semente do gerador pseudoaleatório na sessão antes de chamar `random()`, garantindo que os mesmos nomes e escolhas sejam reproduzidos a cada `reset.sh`.
- **`generate_series` + arrays:** gera lotes grandes de registros em uma única instrução SQL declarativa (sem loops procedurais), combinando índices aleatórios sobre arrays de prenomes e sobrenomes.
- **Unicidade sem colisão:** matrícula e e-mail usam o índice sequencial (`lpad(...)`), evitando colisões `UNIQUE` mesmo quando dois usuários sorteiam o mesmo nome completo.
- **IDs de demonstração fixos:** usuários `1..4` (2 alunos, 1 professor, 1 admin) e sala `5` (`A-105`) ficam conhecidos desde o início para testes manuais, CLI e concorrência sem interferência da carga massiva futura.
