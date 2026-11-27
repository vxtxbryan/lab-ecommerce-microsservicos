#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from pathlib import Path
import re
import yaml

repo = "https://github.com/vxtxbryan/lab-ecommerce-microsservicos.git"
services = ("products", "orders", "users", "payments")

def load(path):
    with Path(path).open() as stream:
        return yaml.safe_load(stream)

root = load("gitops/bootstrap/root-application.yaml")
assert root["kind"] == "Application" and root["metadata"]["name"] == "ecommerce-root"
assert root["spec"]["source"]["repoURL"] == repo
assert root["spec"]["source"]["targetRevision"] == "main"
assert root["spec"]["source"]["path"] == "gitops/apps"
assert root["spec"]["source"]["directory"]["recurse"] is True
assert root["spec"]["syncPolicy"]["automated"]["prune"] is True
assert root["spec"]["syncPolicy"]["syncOptions"] == ["PruneLast=true"]

project = load("gitops/apps/project.yaml")
assert project["kind"] == "AppProject" and project["metadata"]["name"] == "ecommerce"
assert project["spec"]["sourceRepos"] == [repo]
assert project["spec"]["clusterResourceWhitelist"] == []

for service in services:
    app = load(f"gitops/apps/{service}.yaml")
    spec = app["spec"]
    assert app["kind"] == "Application" and app["metadata"]["name"] == service
    assert spec["project"] == "ecommerce"
    assert len(spec["sources"]) == 2
    chart, values = spec["sources"]
    assert chart["repoURL"] == values["repoURL"] == repo
    assert chart["targetRevision"] == values["targetRevision"] == "main"
    assert chart["path"] == "helm/microservice" and values["ref"] == "values"
    assert chart["helm"]["releaseName"] == service
    assert chart["helm"]["valueFiles"] == [f"$values/helm/values/{service}.yaml"]
    assert spec["destination"]["namespace"] == "default"
    assert spec["syncPolicy"]["automated"]["prune"] is True
    assert spec["syncPolicy"]["syncOptions"] == ["PruneLast=true"]

    values_file = load(f"helm/values/{service}.yaml")
    tag = values_file["image"]["tag"]
    assert tag == "" or re.fullmatch(r"[0-9a-f]{40}", tag)
    assert values_file["serviceAccount"]["roleArn"].startswith("arn:aws:iam::")
    assert values_file["env"].get(f"{service.upper()}_TABLE")
    assert values_file["serviceMonitor"]["enabled"] is True

print("Configuração GitOps validada para root app, projeto e quatro serviços.")
PY
