#!/usr/bin/env bash
# Run on the approved Linux host, with Docker access provided by the operator.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
: "${SRE_SECRETS_DIR:?set the private secret directory}"
: "${SRE_IMAGE_TAG:?set the reviewed immutable commit tag}"
if [[ -n "${COMPOSE_PROFILES:-}" ]]; then
  echo 'BLOCKED: deployment does not enable host-exporter or other profiles' >&2
  exit 1
fi
export COMPOSE_PROFILES=
compose() { docker compose -p homelab-sre-prod -f compose.yaml -f compose.hardened.yaml "$@"; }
compose config --format json | python3 scripts/check-deployment.py --secrets-dir "$SRE_SECRETS_DIR"
# Build first using the documented, resource-bounded operator command. Never
# silently replace the reviewed image with a moving registry tag here.
[[ "$SRE_IMAGE_TAG" =~ ^[0-9a-f]{40}$ ]] || { echo 'A full reviewed commit hash is required' >&2; exit 1; }
revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "homelab-sre-observability/demo-api:$SRE_IMAGE_TAG")"
[[ "$revision" == "$SRE_IMAGE_TAG" ]] || { echo 'Image provenance does not match requested commit' >&2; exit 1; }
compose up --detach --no-build --wait --wait-timeout 180
for target in \
  "http://127.0.0.1:${SRE_API_PORT:-8080}/health/ready" \
  "http://127.0.0.1:${SRE_PROMETHEUS_PORT:-9090}/-/ready" \
  "http://127.0.0.1:${SRE_ALERTMANAGER_PORT:-9093}/-/ready" \
  "http://127.0.0.1:${SRE_GRAFANA_PORT:-3000}/api/health"; do
  ready=0
  for _ in {1..60}; do
    if curl --max-time 3 -fsS "$target" >/dev/null; then ready=1; break; fi
    sleep 2
  done
  [[ "$ready" == 1 ]] || { echo 'Readiness failed; preserve evidence and roll back this project only.' >&2; exit 1; }
done
status="$(curl --max-time 3 -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SRE_API_PORT:-8080}/work?fail=true")"
[[ "$status" == 403 ]] || { echo 'Fault controls are unexpectedly accessible' >&2; exit 1; }
status="$(curl --max-time 3 -sS -X POST -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SRE_API_PORT:-8080}/admin/readiness?ready=false")"
[[ "$status" == 404 ]] || { echo 'Readiness injection is unexpectedly accessible' >&2; exit 1; }
echo 'Isolated hardened stack is ready. Independent paging and recovery acceptance remain operator gates.'
