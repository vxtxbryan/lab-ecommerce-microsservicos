import json

from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from common.telemetry import configure_telemetry


def test_metrics_use_route_templates_and_logs_omit_sensitive_data(capsys):
    app = FastAPI()
    configure_telemetry(app, "test")

    @app.post('/users/{user_id}')
    def user(user_id: str):
        raise HTTPException(401, "denied")

    with TestClient(app) as client:
        for user_id in ("private-id-a", "private-id-b"):
            assert client.post(f'/users/{user_id}?password=secret-query',
                               json={"password": "secret-body"},
                               headers={"Authorization": "Bearer secret-header"}).status_code == 401
        assert client.get('/unknown-private-path').status_code == 404
        metrics = client.get('/metrics').text
        assert 'route="/users/{user_id}"' in metrics
        assert 'route="unmatched"' in metrics
        assert 'status="401"' in metrics
        assert 'route="/metrics"' not in metrics
    logs = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert len(logs) == 3
    assert logs[0]['route'] == '/users/{user_id}'
    assert logs[0]['status'] == 401
    assert logs[0]['duration_ms'] >= 0
    for secret in ('private-id', 'secret-query', 'secret-body', 'secret-header', 'unknown-private-path'):
        assert secret not in metrics
        assert secret not in json.dumps(logs)


def test_unhandled_exception_is_counted_as_500(capsys):
    app = FastAPI()
    configure_telemetry(app, "test")

    @app.get('/fail')
    def fail():
        raise RuntimeError('internal')

    with TestClient(app, raise_server_exceptions=False) as client:
        assert client.get('/fail').status_code == 500
        assert 'status="500"' in client.get('/metrics').text
    assert json.loads(capsys.readouterr().out)['status'] == 500
