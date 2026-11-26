FROM python:3.12-slim

RUN apt-get update && apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY services/orders/requirements.txt .
COPY common/requirements.txt /tmp/telemetry-requirements.txt
RUN pip install --no-cache-dir -r requirements.txt -r /tmp/telemetry-requirements.txt

COPY services/orders/ .
COPY common/ /app/common/

ENV PYTHONDONTWRITEBYTECODE=1
USER 10001:10001

EXPOSE 8001

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
