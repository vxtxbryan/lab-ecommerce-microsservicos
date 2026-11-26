"""HTTP metrics with bounded labels and structured request logs."""
from datetime import datetime, timezone
import json
import logging
import sys
import time

from fastapi import Response
from prometheus_client import CollectorRegistry, Counter, Histogram, CONTENT_TYPE_LATEST, generate_latest


class JsonFormatter(logging.Formatter):
    def format(self, record):
        data = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        data.update(getattr(record, "request_fields", {}))
        return json.dumps(data, ensure_ascii=False)


class RequestTelemetry:
    def __init__(self, app, service, requests, duration):
        self.app, self.service = app, service
        self.requests, self.duration = requests, duration
        self.logger = logging.getLogger("ecommerce.requests")

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["path"] in {"/health", "/metrics"}:
            return await self.app(scope, receive, send)
        start, status = time.perf_counter(), 500

        async def record_status(message):
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, record_status)
        finally:
            # Template route prevents IDs and arbitrary URLs from creating time series.
            route = getattr(scope.get("route"), "path", "unmatched")
            method = scope["method"] if scope["method"] in {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"} else "OTHER"
            elapsed = time.perf_counter() - start
            self.requests.labels(self.service, method, route, str(status)).inc()
            self.duration.labels(self.service, method, route).observe(elapsed)
            self.logger.info("http_request", extra={"request_fields": {
                "service": self.service, "method": method, "route": route,
                "status": status, "duration_ms": round(elapsed * 1000, 2),
            }})


def configure_telemetry(app, service):
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("ecommerce.requests")
    logger.handlers = [handler]
    logger.propagate = False
    logger.setLevel(logging.INFO)
    # Avoid unstructured access logs that include raw URLs/query strings.
    logging.getLogger("uvicorn.access").disabled = True
    registry = CollectorRegistry()
    requests = Counter("ecommerce_http_requests_total", "Completed HTTP requests",
                       ["service", "method", "route", "status"], registry=registry)
    duration = Histogram("ecommerce_http_request_duration_seconds", "HTTP latency",
                         ["service", "method", "route"], registry=registry)

    @app.get("/metrics", include_in_schema=False)
    def metrics():
        return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)

    app.add_middleware(RequestTelemetry, service=service, requests=requests, duration=duration)
