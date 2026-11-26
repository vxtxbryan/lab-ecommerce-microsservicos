COMPOSE := docker compose
.PHONY: up down test validate charts fmt deploy clean
up:
	$(COMPOSE) up --build -d
down:
	$(COMPOSE) down
test:
	python3 -m pytest -q tests
validate: charts fmt
	@for script in scripts/*.sh; do bash -n "$$script" || exit; done
	$(COMPOSE) config --quiet
charts:
	bash scripts/validate-charts.sh /tmp/ecommerce-rendered
fmt:
	terraform -chdir=infra/terraform fmt -check -recursive
deploy:
	bash scripts/deploy-services.sh
clean:
	$(COMPOSE) down --volumes
