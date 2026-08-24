#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for command in docker curl jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "required smoke-test command is missing: $command" >&2
    exit 1
  }
done

export GRAFANA_ADMIN_USER=smoke-admin
export GRAFANA_ADMIN_PASSWORD=smoke-validation-only-not-a-secret

cleanup() {
  local result="$1"
  trap - EXIT
  if [[ "$result" -ne 0 ]]; then
    docker compose ps || true
    docker compose logs --no-color --tail 200 || true
  fi
  docker compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  exit "$result"
}
trap 'cleanup $?' EXIT

wait_for() {
  local description="$1"
  local attempt
  shift
  for ((attempt = 1; attempt <= 60; attempt++)); do
    if "$@" >/dev/null 2>&1; then
      echo "ready: $description"
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for $description" >&2
  return 1
}

query_has_result() {
  local query="$1"
  curl -fsS --get --data-urlencode "query=$query" \
    http://127.0.0.1:9090/api/v1/query \
    | jq -e '.status == "success" and (.data.result | length > 0)' >/dev/null
}

docker compose up --build --detach

wait_for "demo API" curl -fsS http://127.0.0.1:8080/health/ready
wait_for "Prometheus" curl -fsS http://127.0.0.1:9090/-/ready
wait_for "Alertmanager" curl -fsS http://127.0.0.1:9093/-/ready
wait_for "Grafana" curl -fsS http://127.0.0.1:3000/api/health
wait_for "demo API scrape" query_has_result 'up{job="demo-api"} == 1'
wait_for "black-box success" query_has_result 'probe_success{job="blackbox-http"} == 1'

curl -fsS 'http://127.0.0.1:8080/work' >/dev/null
failure_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  'http://127.0.0.1:8080/work?fail=true')"
[[ "$failure_status" == "503" ]] || {
  echo "injected work failure returned HTTP $failure_status, want 503" >&2
  exit 1
}
wait_for "bounded 5xx metric" query_has_result \
  'sre_demo_http_requests_total{route="/work",status_class="5xx"} >= 1'

curl -fsS -X POST \
  'http://127.0.0.1:8080/admin/readiness?ready=false' >/dev/null
readiness_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  http://127.0.0.1:8080/health/ready)"
[[ "$readiness_status" == "503" ]] || {
  echo "failed readiness returned HTTP $readiness_status, want 503" >&2
  exit 1
}
curl -fsS http://127.0.0.1:8080/health/live >/dev/null
wait_for "observed readiness failure" query_has_result \
  'probe_success{job="blackbox-http"} == 0'

curl -fsS -X POST \
  'http://127.0.0.1:8080/admin/readiness?ready=true' >/dev/null
wait_for "observed readiness recovery" query_has_result \
  'probe_success{job="blackbox-http"} == 1'

curl -fsS http://127.0.0.1:3000/api/health \
  | jq -e '.database == "ok"' >/dev/null

echo "end-to-end smoke test passed"
