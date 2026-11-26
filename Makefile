COMPOSE := docker compose
.PHONY: up down test validate charts fmt deploy clean monitoring monitoring-test alerts-test
up:
	$(COMPOSE) up --build -d
down:
	$(COMPOSE) down
test:
	ORDERS_TEST_URL=http://localhost:8001 USERS_TEST_URL=http://localhost:8002 STOCK_TEST_URL=http://localhost:8000 PAYMENT_TEST_URL=http://localhost:8003 python3 -m pytest -q tests
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

monitoring:
	bash scripts/install-monitoring.sh

monitoring-test:
	bash scripts/test-monitoring.sh

alerts-test:
	bash scripts/test-alerts.sh
