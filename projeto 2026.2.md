## **Projeto: Sistema de Reserva de Salas e Laboratórios**

### **1\. Visão geral**

Uma aplicação simples (CLI ou web mínima) para reservar salas e laboratórios de uma instituição. **A aplicação é só uma “casca”**: toda regra de negócio importante deve estar no PostgreSQL (constraints, triggers, functions, views, permissões). 

**Duração:** 10 dias

* **Equipe:** 2 alunos  
* **Linguagem da aplicação:** livre (Python com psycopg, Java com JDBC, Node com pg, etc.)  
* **Proibido:** ORM que esconda o SQL. Os alunos devem escrever SQL de verdade.

### **2\. Funcionalidades da aplicação (só 4\)**

1. Listar a agenda de uma sala em um dia (consulta a uma view).  
2. Criar reserva (chama uma function/procedure do banco).  
3. Cancelar reserva (chama uma function/procedure).  
4. Exibir relatório de ocupação por sala no mês (consulta a uma view ou materialized view).

**OBSERVAÇÃO: para realização dos testes e demonstração, o banco de dados deve estar populado com salas, alunos e recursos.** 

A aplicação **não pode** validar conflito de horário, limite de reservas ou capacidade. Quem faz isso é o banco.

### **3\. Requisitos do banco (o núcleo do projeto)**

**3.1 Modelagem**

* Mínimo de 5 tabelas, por exemplo: `usuario`, `sala`, `recurso` (projetor, computadores etc.), `sala_recurso` (N:N), `reserva`, `log_reserva`.  
* DER (conceitual e lógico) e justificativa de que o esquema está na 3FN.

**3.2 Integridade declarativa**

* PK, FK com `ON DELETE` justificado, `UNIQUE`, `NOT NULL`, `CHECK`, e pelo menos um `DOMAIN` ou `ENUM` (ex.: status da reserva).  
* **Obrigatório:** impedir sobreposição de reservas na mesma sala com `EXCLUDE USING gist` e `tstzrange`. Exemplo de ideia:

sql  
CREATE EXTENSION IF NOT EXISTS btree\_gist;  
ALTER TABLE reserva ADD CONSTRAINT sem\_conflito  
  EXCLUDE USING gist (sala\_id WITH \=, periodo WITH &&)  
  WHERE (status \= 'ATIVA');

**3.3 Programação no banco**

* 2 triggers: (a) auditoria, gravando em `log_reserva` toda inserção, alteração e cancelamento; (b) regra de negócio, por exemplo um usuário não pode ter mais de 3 reservas ativas futuras, ou a reserva não pode ultrapassar a duração máxima.  
* 2 functions/procedures: `criar_reserva(...)`, que valida e insere dentro de transação, e `taxa_ocupacao(sala, mes)`.  
* Tratamento de erro com `RAISE EXCEPTION` e mensagens claras, que a aplicação apenas repassa ao usuário.

**3.4 Consultas e desempenho**

* 2 views (`v_agenda_dia`, `v_reservas_usuario`) e 1 materialized view (ocupação mensal).  
* 5 consultas analíticas documentadas, usando JOIN, GROUP BY/HAVING, subconsulta, CTE e pelo menos uma window function (ex.: `RANK() OVER`).  
* Popular com pelo menos 10 mil reservas usando `generate_series`/`random()`.  
* Criar 2 índices e comparar `EXPLAIN ANALYZE` antes e depois (prints e análise).

**3.5 Transações, concorrência e segurança**

* Demonstrar com duas sessões simultâneas que dois usuários não conseguem reservar o mesmo horário (documentar o roteiro e o resultado).  
* Criar uma role `app_reservas` com permissão apenas de `EXECUTE` nas functions e `SELECT` nas views, sem acesso direto às tabelas.

**PARA APRESENTAÇÃO SERÁ REALIZADA UMA AVALIAÇÃO ORAL DO TRABALHO. VOU FAZER PERGUNTA AOS DOIS INTEGRANTES DA DUPLA.** 

**A NOTA SERÁ COMPUTADA DA SEGUINTE FORMA:** 

* **50% IMPLEMENTAÇÃO**  
* **50% AVALIAÇÃO ORAL E INDIVIDUAL DO TRABALHO**