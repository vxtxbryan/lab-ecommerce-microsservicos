#!/usr/bin/env bash
# Requer Helm, Python/PyYAML e Docker. Cria apenas um container temporário.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
helm template ecommerce-observability helm/observability --show-only templates/alerts.yaml > "$work/rendered.yaml"
python3 - "$work" <<'PY'
import pathlib, sys, yaml
work = pathlib.Path(sys.argv[1])
rule = yaml.safe_load((work / 'rendered.yaml').read_text())
(work / 'alerts.yaml').write_text(yaml.safe_dump(rule['spec']))
PY
cp tests/monitoring/rules.test.yaml "$work/rules.test.yaml"
chmod 755 "$work"
chmod 644 "$work"/*.yaml
docker run --rm --entrypoint /bin/promtool -v "$work:/rules:ro" -w /rules \
  prom/prometheus:v3.16.0 test rules rules.test.yaml
