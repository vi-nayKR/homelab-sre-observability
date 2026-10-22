#!/usr/bin/env bash
# Cold backup + isolated file-restore drill. NEVER restores over live volumes.
set -euo pipefail
[[ "${1:-}" == --offline && -n "${2:-}" ]] || { echo "Usage: $0 --offline PRIVATE_BACKUP_DIRECTORY" >&2; exit 1; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
: "${SRE_SECRETS_DIR:?set the private secret directory}"
: "${SRE_IMAGE_TAG:?set the reviewed commit tag}"
export COMPOSE_PROFILES=
compose() { docker compose -p homelab-sre-prod -f compose.yaml -f compose.hardened.yaml "$@"; }
compose config --format json | python3 scripts/check-deployment.py --secrets-dir "$SRE_SECRETS_DIR"
volumes=(homelab-sre-prod_prometheus-data homelab-sre-prod_alertmanager-data homelab-sre-prod_grafana-data)
for volume in "${volumes[@]}"; do
  project="$(docker volume inspect --format '{{index .Labels "com.docker.compose.project"}}' "$volume")"
  [[ "$project" == homelab-sre-prod ]] || { echo 'Refusing a volume outside this project' >&2; exit 1; }
done
umask 077
mkdir -p "$2"
chmod 0700 "$2"
backup="$(cd "$2" && pwd)/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -m 0700 "$backup"
image=prom/prometheus:v3.14.0@sha256:5ce7540c3c00ef4ab0c9d2c995c6a5b9c421f44b4a115d97a2c7af3b1c21cbb0
restores=()
cleanup() {
  result=$?
  trap - EXIT
  for volume in "${restores[@]}"; do docker volume rm "$volume" >/dev/null || result=1; done
  compose up --no-build --detach --wait --wait-timeout 180 || result=1
  exit "$result"
}
trap cleanup EXIT
# Only this namespace is paused. This is a declared monitoring maintenance gap.
compose stop
for volume in "${volumes[@]}"; do
  docker run --rm --network none --read-only --user 0:0 \
    --cap-drop ALL --cap-add DAC_OVERRIDE --security-opt no-new-privileges:true \
    --memory 128m --cpus 0.25 \
    --mount "type=volume,src=$volume,dst=/source,readonly" \
    --mount "type=bind,src=$backup,dst=/backup" \
    --entrypoint /bin/sh "$image" -c \
    'set -eu; cd /source; tar czf "/backup/$1.tgz" .; find . -type f -exec sha256sum {} \; | sort > "/backup/$1.files.sha256"' sh "$volume"
  restore="homelab-sre-restore-check-$$-${volume##*_}"
  [[ -z "$(docker volume ls -q --filter name="^${restore}$")" ]] || { echo 'Restore fixture name already exists' >&2; exit 1; }
  docker volume create --label sre.restore-check=true "$restore" >/dev/null
  restores+=("$restore")
  docker run --rm --network none --read-only --user 0:0 \
    --cap-drop ALL --cap-add DAC_OVERRIDE --cap-add CHOWN --cap-add FOWNER \
    --security-opt no-new-privileges:true --memory 128m --cpus 0.25 \
    --mount "type=volume,src=$restore,dst=/restore" \
    --mount "type=bind,src=$backup,dst=/backup,readonly" \
    --entrypoint /bin/sh "$image" -c \
    'set -eu; cd /restore; tar xzf "/backup/$1.tgz"; if test -s "/backup/$1.files.sha256"; then sha256sum -c "/backup/$1.files.sha256" >/dev/null; fi' sh "$volume"
done
(cd "$backup" && sha256sum ./*.tgz > SHA256SUMS && sha256sum -c SHA256SUMS)
printf 'commit=%s\ncompleted_utc=%s\nscope=cold volume archive and isolated file-content restore verification\n' \
  "$SRE_IMAGE_TAG" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$backup/RESTORE_VERIFIED.txt"
echo 'Cold backup and isolated file restore checks passed. This is not full application RTO or off-host recovery proof.'
