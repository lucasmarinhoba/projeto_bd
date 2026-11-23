-include .env
export

COMPOSE = docker compose
EXEC    = $(COMPOSE) exec -T db

.PHONY: up down reset psql test app

up:
	$(COMPOSE) up -d --wait

down:
	$(COMPOSE) down

# 99_reset.sql roda primeiro, depois sql/0*.sql (ver scripts/reset.sh)
reset: up
	$(EXEC) sh /projeto/scripts/reset.sh

psql:
	$(COMPOSE) exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

test:
	$(EXEC) sh /projeto/scripts/test.sh

app:
	python app/main.py

web:
	python app/main.py --web
