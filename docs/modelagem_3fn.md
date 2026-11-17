# Modelagem Relacional, Normalização (1FN, 2FN, 3FN) e Integridade Referencial

Este documento justifica que o esquema do schema `reservas` atende à **Terceira Forma Normal (3FN)** — e, para as relações operacionais, também à **Forma Normal de Boyce-Codd (BCNF)** — além de documentar escolhas deliberadas de modelagem e as ações de `ON DELETE`.

---

## 1. Análise de Dependências Funcionais e Normalização por Tabela

Em todas as 6 tabelas abaixo, **100% dos atributos** constam explicitamente nas dependências funcionais analisadas.

### 1.1 `usuario`
* **Atributos:** `id`, `matricula`, `nome`, `email`, `tipo`, `ativo`, `criado_em`
* **Chave Primária (PK):** `{id}` (substituta, `GENERATED ALWAYS AS IDENTITY`)
* **Chaves Candidatas (UK):** `{matricula}`, `{email}`
* **Dependências Funcionais (DFs):**
  * `id → matricula, nome, email, tipo, ativo, criado_em`
  * `matricula → id, nome, email, tipo, ativo, criado_em`
  * `email → id, matricula, nome, tipo, ativo, criado_em`
* **Verificação das Formas Normais:**
  * **1FN:** Todos os atributos têm valores atômicos e escalares (sem grupos repetitivos nem múltiplos e-mails/telefones na mesma coluna).
  * **2FN:** Chave primária simples (`id`) — não há possibilidade de dependência parcial.
  * **3FN:** Nenhum atributo não-chave determina outro atributo não-chave (ex.: `tipo` não determina `ativo`, `matricula` e `email` são superchaves/chaves candidatas). Logo, sem dependências transitivas.

### 1.2 `sala`
* **Atributos:** `id`, `codigo`, `nome`, `tipo`, `capacidade`, `ativa`
* **Chave Primária (PK):** `{id}`
* **Chave Candidata (UK):** `{codigo}`
* **Dependências Funcionais (DFs):**
  * `id → codigo, nome, tipo, capacidade, ativa`
  * `codigo → id, nome, tipo, capacidade, ativa`
* **Verificação das Formas Normais:**
  * **1FN:** Valores atômicos; recursos da sala não ficam em lista/array dentro de `sala`, pois foram extraídos para `recurso` e `sala_recurso`.
  * **2FN:** PK simples (`id`), sem dependências parciais.
  * **3FN:** `codigo` é chave candidata (`UNIQUE`), e nenhum atributo não-chave (`nome`, `tipo`, `capacidade`, `ativa`) determina funcionalmente outro. Mesmo que salas do tipo `LABORATORIO` costumem ter faixas diferentes de capacidade, `tipo` não determina `capacidade` nem `nome`.

### 1.3 `recurso`
* **Atributos:** `id`, `nome`
* **Chave Primária (PK):** `{id}`
* **Chave Candidata (UK):** `{nome}`
* **Dependências Funcionais (DFs):**
  * `id → nome`
  * `nome → id`
* **Verificação das Formas Normais:**
  * **1FN, 2FN e 3FN:** Relação binária composta apenas por duas chaves candidatas (`id` e `nome`), sem atributos não-chave extras. Está em 1FN, 2FN, 3FN e BCNF.

### 1.4 `sala_recurso`
* **Atributos:** `sala_id`, `recurso_id`, `quantidade`
* **Chave Primária (PK):** `{sala_id, recurso_id}` (composta)
* **Chaves Candidatas:** `{sala_id, recurso_id}`
* **Dependências Funcionais (DFs):**
  * `(sala_id, recurso_id) → quantidade`
* **Verificação das Formas Normais:**
  * **1FN:** Cada linha associa exatamente uma sala a um recurso com uma `quantidade` inteira positiva (`qtd_positiva`).
  * **2FN (ponto crítico):** Como a PK é composta, é obrigatório verificar que não existem dependências parciais. `quantidade` depende da **chave inteira** `(sala_id, recurso_id)` — nem `sala_id` sozinho nem `recurso_id` sozinho determinam quantas unidades daquele recurso existem naquela sala (ex.: Sala B-01 tem 30 `Computadores`, enquanto Sala B-02 tem 20). Atributos da sala (como `capacidade`) ou do recurso (como `nome`) ficam em suas tabelas originais.
  * **3FN:** Existe apenas um atributo não-chave (`quantidade`), impossibilitando dependência transitiva entre atributos não-chave.

### 1.5 `reserva`
* **Atributos:** `id`, `usuario_id`, `sala_id`, `periodo`, `qtd_participantes`, `finalidade`, `status`, `criada_em`, `cancelada_em`, `motivo_cancelamento`
* **Chave Primária (PK):** `{id}`
* **Chaves Candidatas:** `{id}` (além da restrição parcial de exclusão `(sala_id, periodo)` para `status = 'ATIVA'`)
* **Dependências Funcionais (DFs):**
  * `id → usuario_id, sala_id, periodo, qtd_participantes, finalidade, status, criada_em, cancelada_em, motivo_cancelamento`
* **Verificação das Formas Normais:**
  * **1FN:** Todos os atributos armazenam valores únicos e atômicos, incluindo `periodo` (`tstzrange`, detalhado na seção 4).
  * **2FN:** PK simples (`id`), sem dependências parciais.
  * **3FN:** Não há dependências transitivas. Dados descritivos do solicitante ou da sala são obtidos por `JOIN` via `usuario_id` e `sala_id`. Observação sobre `(status, cancelada_em, motivo_cancelamento)`: `status = 'CANCELADA'` obriga `cancelada_em IS NOT NULL` (regra de consistência `ck_cancelamento_coerente`), mas não determina o instante exato `cancelada_em` nem o texto `motivo_cancelamento` — ambos dependem diretamente do evento da reserva `id`.

### 1.6 `log_reserva`
* **Atributos:** `id`, `reserva_id`, `operacao`, `dados_antigos`, `dados_novos`, `usuario_db`, `data_hora`
* **Chave Primária (PK):** `{id}`
* **Chaves Candidatas:** `{id}`
* **Dependências Funcionais (DFs):**
  * `id → reserva_id, operacao, dados_antigos, dados_novos, usuario_db, data_hora`
* **Verificação das Formas Normais:**
  * **1FN / 2FN / 3FN:** PK simples (`id`) e nenhum atributo não-chave determina funcionalmente outro. O uso de `jsonb` nos snapshots é tratado especificamente na seção 3 como desnormalização intencional.

---

## 2. Atributos Deliberadamente Não Armazenados

Para preservar a 3FN e evitar anomalias de atualização ou redundância derivada, os seguintes atributos foram **intencionalmente omitidos**:

| Atributo omitido | Onde poderia aparecer | Por que foi omitido |
|---|---|---|
| `nome_usuario`, `email_usuario`, `matricula` | `reserva` | Violaram a 3FN por dependência transitiva (`reserva.id → usuario_id → nome_usuario`). Se o usuário alterasse o e-mail ou nome, seria necessário atualizar N linhas de `reserva`. |
| `codigo_sala`, `nome_sala`, `capacidade_sala` | `reserva` | Dependência transitiva (`reserva.id → sala_id → capacidade_sala`). Obtidos via `JOIN` nas views e consultas. |
| `recursos` (lista/texto em `sala`) | `sala` | Violaria a 1FN (atributo multivalorado). Modelado pela relação N:N `sala_recurso`. |
| Status `'CONCLUIDA'` em `status_reserva` | `reserva.status` | É dado derivado do tempo (`status = 'ATIVA' AND upper(periodo) <= now()`). Armazená-lo exigiria *jobs* para atualizar linhas antigas e criaria risco de divergência entre relógio e status. |
| `duracao` (`interval`) | `reserva` | Dado derivado de `upper(periodo) - lower(periodo)`. Guardá-lo em coluna separada duplicaria informação e poderia dessincronizar em um `UPDATE`. |

---

## 3. Nota sobre `log_reserva`: Trilha de Auditoria *Append-Only* e `jsonb`

A tabela `log_reserva` registra o histórico imutável (*append-only*) das alterações em `reserva`, gravando `dados_antigos` e `dados_novos` como documentos `jsonb` via `to_jsonb(OLD)` e `to_jsonb(NEW)` no trigger `trg_audit_reserva`.

Do ponto de vista estritamente relacional, armazenar um snapshot `jsonb` com os campos da tupla de `reserva` constitui uma **desnormalização intencional e tecnicamente justificada**:
1. **Imutabilidade histórica:** um log de auditoria deve retratar exatamente o estado do registro **no instante da operação** (ex.: qual era o `periodo` ou `qtd_participantes` antes do `UPDATE` ou cancelamento), sem sofrer mutações retroativas caso o registro ou o esquema evoluam no futuro.
2. **Desacoplamento de schema:** alterações futuras de colunas em `reserva` não quebram a estrutura da auditoria nem exigem reescrita de registros históricos antigos.
3. **Sem impacto operacional:** a tabela nunca sofre `UPDATE` ou `DELETE` na aplicação (apenas `INSERT` pelo trigger `SECURITY DEFINER`), eliminando anomalias de atualização.

---

## 4. Discussão de Design: `periodo tstzrange` vs. Duas Colunas (`inicio`, `fim`)

Optou-se por modelar o intervalo da reserva como uma única coluna `periodo` do tipo nativo `tstzrange` com limites meio-abertos **`[)`** (fechado no início, aberto no fim):

1. **Conformidade com a 1FN:** no PostgreSQL, um *range type* (`tstzrange`) é um **tipo escalar de primeira classe** que representa um domínio contínuo único com álgebra e operadores próprios (`&&`, `@>`, `lower()`, `upper()`, `isempty()`), não um grupo repetitivo de valores distintos.
2. **Prevenção atômica de conflitos (`EXCLUDE USING gist`):** `tstzrange` permite declarar diretamente `EXCLUDE USING gist (sala_id WITH =, periodo WITH &&) WHERE (status = 'ATIVA')`, usando o índice GiST de forma nativa e sem depender de índice funcional sobre `tstzrange(inicio, fim, '[)')`.
3. **Semântica `[)` para reservas adjacentes:** com início inclusivo e fim exclusivo, `08:00–10:00` (`[08:00, 10:00)`) e `10:00–12:00` (`[10:00, 12:00)`) **não se sobrepõem** (`&&` retorna `false`), evitando falsos conflitos na troca de turmas.
4. **Invariantes garantidas no domínio da coluna:** a constraint `ck_periodo_valido` impede intervalos vazios (`NOT isempty`), infinitos (`NOT lower_inf`, `NOT upper_inf`) ou com limites diferentes de `[)` (`lower_inc AND NOT upper_inc`), além de o próprio tipo `tstzrange` impedir estruturalmente `fim < início`.
5. **Alternativa comparada:** usar duas colunas `inicio timestamptz` e `fim timestamptz` exigiria `CHECK (fim > inicio)` separado e um `EXCLUDE USING gist (sala_id WITH =, tstzrange(inicio, fim, '[)') WITH &&)`, além de obrigar a repetição exata da expressão funcional `tstzrange(inicio, fim, '[)')` nas consultas para o planner aproveitar o índice.

---

## 5. Ações de Integridade Referencial (`ON DELETE`)

Todas as chaves estrangeiras possuem comportamento explícito e justificado para proteger a integridade histórica do banco:

| Chave Estrangeira (FK) | Tabela Referenciada | Ação `ON DELETE` | Justificativa |
|---|---|---|---|
| `reserva.usuario_id` | `usuario(id)` | **`RESTRICT`** | Histórico de reservas e auditoria não podem ser apagados nem ficar órfãos. Quando um usuário sai da instituição, ele é **desativado** logicamente (`ativo = false`). |
| `reserva.sala_id` | `sala(id)` | **`RESTRICT`** | Preserva o histórico de ocupação e métricas mensais das salas. Salas desativadas ou em reforma recebem `ativa = false`. |
| `sala_recurso.sala_id` | `sala(id)` | **`CASCADE`** | `sala_recurso` é entidade associativa fraca que descreve o inventário de uma sala específica; se uma sala recém-criada (sem reservas) for removida, sua lista de recursos não tem sentido isolado. |
| `sala_recurso.recurso_id` | `recurso(id)` | **`RESTRICT`** | Impede que um tipo de recurso (ex.: `Projetor`) seja excluído acidentalmente enquanto ainda estiver associado a alguma sala. |
| `log_reserva.reserva_id` | `reserva(id)` | **`RESTRICT`** | Garante que a trilha de auditoria seja imutável; uma reserva nunca deve ser excluída fisicamente (`DELETE`), devendo apenas mudar para `status = 'CANCELADA'` via `UPDATE`. |
