#!/usr/bin/env bash
# Consulta Prometheus e Grafana a partir da rede do cluster, sem exposição pública.
set -euo pipefail
kubectl exec -i -n default deployment/orders -- python - <<'PY'
import time
import httpx

base = 'http://monitoring-kube-prometheus-prometheus.monitoring:9090'
with httpx.Client(timeout=15) as client:
    deadline = time.monotonic() + 180
    while True:
        response = client.get(base + '/api/v1/targets')
        response.raise_for_status()
        targets = response.json()['data']['activeTargets']
        apis = {t['labels'].get('service'): t for t in targets
                if t['labels'].get('namespace') == 'default'}
        if all(name in apis and apis[name]['health'] == 'up'
               for name in ('products', 'orders', 'users', 'payments')):
            break
        if time.monotonic() >= deadline:
            raise SystemExit('Prometheus não encontrou as quatro APIs saudáveis')
        time.sleep(5)
    response = client.get(base + '/api/v1/query', params={
        'query': 'sum by (service) (ecommerce_http_requests_total)'
    })
    response.raise_for_status()
    names = {item['metric']['service'] for item in response.json()['data']['result']}
    assert {'products', 'orders', 'users', 'payments'} <= names, names
    rules = client.get(base + '/api/v1/rules').json()['data']['groups']
    names = {rule['name'] for group in rules for rule in group['rules']}
    assert {'EcommerceTargetDown', 'EcommerceDeploymentUnavailable',
            'EcommerceHighErrorRate', 'EcommerceHighLatency'} <= names
    assert client.get('http://monitoring-grafana.monitoring/api/health').json()['database'] == 'ok'
    print('Prometheus: quatro targets UP, métricas das quatro APIs e quatro alertas carregados. Grafana saudável.')
PY
kubectl get configmap ecommerce-dashboard -n monitoring -o jsonpath='{.data.ecommerce\.json}' | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["uid"] == "ecommerce-overview"; assert len(d["panels"]) == 10; print("Dashboard: 10 painéis provisionados.")'
