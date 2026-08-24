#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
evidence_directory="$repo_root/evidence/runtime"
mkdir -p "$evidence_directory/queries" "$evidence_directory/alerts"

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

wait_for_up_to() {
  local description="$1"
  local max_attempts="$2"
  local attempt
  shift 2
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if "$@" >/dev/null 2>&1; then
      echo "ready: $description"
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for $description" >&2
  return 1
}

wait_for() {
  local description="$1"
  shift
  wait_for_up_to "$description" 100 "$@"
}

query_has_no_result() {
  local query="$1"
  curl -fsS --get --data-urlencode "query=$query" \
    http://127.0.0.1:9090/api/v1/query \
    | jq -e '.status == "success" and (.data.result | length == 0)' >/dev/null
}

alertmanager_has_alert() {
  local alert_name="$1"
  curl -fsS --get --data-urlencode "filter=alertname=$alert_name" \
    http://127.0.0.1:9093/api/v2/alerts \
    | jq -e --arg alert_name "$alert_name" \
      'any(.[]; .labels.alertname == $alert_name and .status.state == "active")' >/dev/null
}

capture_query() {
  local query="$1"
  local output="$2"
  curl -fsS --get --data-urlencode "query=$query" \
    http://127.0.0.1:9090/api/v1/query \
    | jq . > "$output"
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

{
  printf 'commit=%s\n' "${GITHUB_SHA:-$(git rev-parse HEAD)}"
  printf 'started_utc=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf 'runner_os=%s\n' "$(uname -s)"
  printf 'runner_arch=%s\n' "$(uname -m)"
  printf 'scope=ephemeral single-host Compose readiness incident\n'
} > "$evidence_directory/metadata.txt"
capture_query 'probe_success{job="blackbox-http"}' "$evidence_directory/queries/before.json"

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
wait_for "BlackboxProbeFailed firing in Prometheus" query_has_result \
  'ALERTS{alertname="BlackboxProbeFailed",alertstate="firing"} == 1'
wait_for "BlackboxProbeFailed routed by Alertmanager" alertmanager_has_alert \
  'BlackboxProbeFailed'
wait_for "firing webhook delivered" query_has_result \
  'sre_demo_alertmanager_webhooks_total{status="firing"} >= 1'
capture_query 'probe_success{job="blackbox-http"}' "$evidence_directory/queries/during.json"
capture_query 'ALERTS{alertname="BlackboxProbeFailed"}' "$evidence_directory/alerts/firing-prometheus.json"
curl -fsS --get --data-urlencode 'filter=alertname=BlackboxProbeFailed' \
  http://127.0.0.1:9093/api/v2/alerts | jq . \
  > "$evidence_directory/alerts/firing-alertmanager.json"
printf 'detected_utc=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  >> "$evidence_directory/metadata.txt"

curl -fsS -X POST \
  'http://127.0.0.1:8080/admin/readiness?ready=true' >/dev/null
wait_for "observed readiness recovery" query_has_result \
  'probe_success{job="blackbox-http"} == 1'
wait_for "Prometheus alert resolution" query_has_no_result \
  'ALERTS{alertname="BlackboxProbeFailed",alertstate="firing"}'
# The route's five-minute group interval intentionally applies to resolved
# notifications too. Keep this wait bounded, but long enough to observe that
# configured delivery contract instead of racing it.
wait_for_up_to "resolved webhook delivered" 200 query_has_result \
  'sre_demo_alertmanager_webhooks_total{status="resolved"} >= 1'
capture_query 'probe_success{job="blackbox-http"}' "$evidence_directory/queries/after.json"
capture_query 'sre_demo_alertmanager_webhooks_total' "$evidence_directory/alerts/webhook-counts.json"
printf 'recovered_utc=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  >> "$evidence_directory/metadata.txt"

curl -fsS http://127.0.0.1:3000/api/health \
  | jq -e '.database == "ok"' >/dev/null

echo "end-to-end smoke test passed"
