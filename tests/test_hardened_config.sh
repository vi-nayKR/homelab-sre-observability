#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
secret_dir="$(mktemp -d)"
trap 'rm -rf "$secret_dir"' EXIT
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
export GRAFANA_ADMIN_USER=validation-admin
export GRAFANA_ADMIN_PASSWORD=file-managed-placeholder
unset COMPOSE_PROFILES

docker compose -p homelab-sre-prod -f compose.yaml -f compose.hardened.yaml config --format json \
  | python3 scripts/check-deployment.py --secrets-dir "$secret_dir"

# The ordinary lab model must never pass the deployment gate.
if docker compose -p homelab-sre-prod -f compose.yaml config --format json \
  | python3 scripts/check-deployment.py --secrets-dir "$secret_dir" >/dev/null 2>&1; then
  echo 'ERROR: lab defaults passed the deployment gate' >&2
  exit 1
fi

docker run --rm --entrypoint /bin/amtool \
  --volume "$root/configs/alertmanager:/etc/alertmanager:ro" \
  --volume "$secret_dir/receiver_token:/run/secrets/receiver_token:ro" \
  prom/alertmanager:v0.34.0@sha256:690c7b525f4367aa91f73e2f91c632206d32e97c6384bdbf2fb7a861b420340d \
  check-config /etc/alertmanager/alertmanager.hardened.yml
