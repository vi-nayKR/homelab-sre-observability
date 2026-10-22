#!/usr/bin/env bash
# Destructive fixture cleanup is restricted to an ephemeral GitHub runner.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'This fixture runs only in ephemeral GitHub CI' >&2; exit 1; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
if [[ -n "$(docker ps -aq --filter label=com.docker.compose.project=homelab-sre-prod)" ]]; then
  echo 'Refusing to replace a pre-existing hardened project' >&2
  exit 1
fi
secret_dir="$(mktemp -d)"
python3 - "$secret_dir" <<'PY'
from pathlib import Path
import secrets,sys
root=Path(sys.argv[1])
root.chmod(0o700)
for name in ('grafana_password','receiver_token'):
    path=root/name
    path.write_text(secrets.token_hex(32))
    path.chmod(0o444)
PY
export SRE_SECRETS_DIR="$secret_dir"
SRE_IMAGE_TAG="$(git rev-parse HEAD)"
export SRE_IMAGE_TAG
export GRAFANA_ADMIN_USER=hardened-ci GRAFANA_ADMIN_PASSWORD=file-managed-placeholder
export SRE_API_PORT=8081 SRE_PROMETHEUS_PORT=9091 SRE_ALERTMANAGER_PORT=9094 SRE_GRAFANA_PORT=3001
unset COMPOSE_PROFILES
compose() { docker compose -p homelab-sre-prod -f compose.yaml -f compose.hardened.yaml "$@"; }
cleanup() {
  result=$?
  trap - EXIT
  if [[ "$result" -ne 0 ]]; then compose ps || true; compose logs --tail 100 || true; fi
  compose down --volumes >/dev/null 2>&1 || true
  rm -rf "$secret_dir"
  exit "$result"
}
trap cleanup EXIT
./scripts/deploy-local.sh
wait_query() {
  local query="$1"
  for _ in {1..60}; do
    if curl --max-time 3 -fsS --get --data-urlencode "query=$query" http://127.0.0.1:9091/api/v1/query \
      | jq -e '.status == "success" and (.data.result | length > 0)' >/dev/null; then return 0; fi
    sleep 2
  done
  echo 'Timed out waiting for hardened telemetry' >&2
  return 1
}
wait_query 'up{job="alert-receiver"} == 1'
wait_query 'sre_demo_alertmanager_webhooks_total{job="alert-receiver",alertname="Watchdog",status="firing"} >= 1'
# Configured retention is not historical evidence: the new stack must NOT claim
# complete-window compliance during warm-up.
curl --max-time 3 -fsS --get --data-urlencode 'query=sre_sli:availability:ratio28d' http://127.0.0.1:9091/api/v1/query \
  | jq -e '.data.result | length == 0' >/dev/null
status="$(curl --max-time 3 -sS -X POST -o /dev/null -w '%{http_code}' http://127.0.0.1:9091/-/reload)"
[[ "$status" == 403 || "$status" == 404 ]] || { echo 'Lifecycle endpoint is enabled' >&2; exit 1; }
# Stop only the fixture API. The separately supervised receiver must survive.
compose stop demo-api
compose exec -T alert-receiver /reliability-api healthcheck
wait_query 'up{job="alert-receiver"} == 1'
compose start demo-api
for _ in {1..60}; do
  if curl --max-time 3 -fsS http://127.0.0.1:8081/health/ready >/dev/null; then break; fi
  sleep 2
done
curl --max-time 3 -fsS http://127.0.0.1:8081/health/ready >/dev/null
./scripts/backup-stack.sh --offline "$secret_dir/backups"
curl --max-time 3 -fsS http://127.0.0.1:8081/health/ready >/dev/null
curl --max-time 3 -fsS http://127.0.0.1:3001/api/health >/dev/null
mkdir -p evidence/runtime/hardened
printf '{"fault_controls":"disabled","watchdog":"authenticated_delivery","receiver_during_api_stop":"healthy","api_restart":"recovered","slo_warmup":"no_compliance_claim","cold_backup_file_restore":"verified"}\n' \
  > evidence/runtime/hardened/result.json
echo 'Hardened runtime, receiver isolation, warm-up and restart checks passed'
