#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for command in go jq ruby; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "required command is missing: $command" >&2
    exit 1
  }
done

echo "checking Go formatting, tests and vet"
unformatted="$(gofmt -l ./cmd)"
if [[ -n "$unformatted" ]]; then
  echo "Go files require gofmt:" >&2
  echo "$unformatted" >&2
  exit 1
fi
go test -race ./...
go vet ./...

echo "checking shell syntax and backup-metric behavior"
bash -n scripts/*.sh tests/*.sh
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh tests/*.sh
fi
./tests/test_backup_metrics.sh

echo "checking YAML and dashboard JSON"
ruby -ryaml -e '
  paths = ["compose.yaml"] + Dir.glob("{configs,.github}/**/*.{yaml,yml}")
  paths.sort.each do |path|
    YAML.load_stream(File.read(path))
  rescue StandardError => e
    warn "invalid YAML #{path}: #{e.message}"
    exit 1
  end
'
jq -e . configs/grafana/dashboards/*.json >/dev/null

prometheus_image="prom/prometheus:v3.14.0@sha256:5ce7540c3c00ef4ab0c9d2c995c6a5b9c421f44b4a115d97a2c7af3b1c21cbb0"
alertmanager_image="prom/alertmanager:v0.34.0@sha256:690c7b525f4367aa91f73e2f91c632206d32e97c6384bdbf2fb7a861b420340d"

echo "checking Prometheus configuration and rule tests"
if command -v promtool >/dev/null 2>&1; then
  (
    cd configs/prometheus
    promtool check config prometheus.yml
    cd tests
    promtool test rules rules.test.yml
  )
elif command -v docker >/dev/null 2>&1; then
  docker run --rm --entrypoint /bin/promtool \
    --workdir /etc/prometheus \
    --volume "$repo_root/configs/prometheus:/etc/prometheus:ro" \
    "$prometheus_image" check config prometheus.yml
  docker run --rm --entrypoint /bin/promtool \
    --workdir /etc/prometheus/tests \
    --volume "$repo_root/configs/prometheus:/etc/prometheus:ro" \
    "$prometheus_image" test rules rules.test.yml
else
  echo "promtool or Docker is required for Prometheus validation" >&2
  exit 1
fi

echo "checking Alertmanager configuration"
if command -v amtool >/dev/null 2>&1; then
  amtool check-config configs/alertmanager/alertmanager.yml
elif command -v docker >/dev/null 2>&1; then
  docker run --rm --entrypoint /bin/amtool \
    --volume "$repo_root/configs/alertmanager:/etc/alertmanager:ro" \
    "$alertmanager_image" check-config /etc/alertmanager/alertmanager.yml
else
  echo "amtool or Docker is required for Alertmanager validation" >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  echo "checking Compose model and demo image build"
  export GRAFANA_ADMIN_USER=ci-admin
  export GRAFANA_ADMIN_PASSWORD=ci-validation-only-not-a-secret
  docker compose config --quiet
  docker compose build demo-api
elif [[ "${REQUIRE_CONTAINER_VALIDATION:-0}" == "1" ]]; then
  echo "Docker is required because REQUIRE_CONTAINER_VALIDATION=1" >&2
  exit 1
else
  echo "Docker unavailable: Compose model and image build are deferred to CI"
fi

echo "all available validation gates passed"
