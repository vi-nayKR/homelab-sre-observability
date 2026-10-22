# Isolated single-host deployment and recovery

This is a hardened **single-host** deployment, not a claim of HA, achieved SLOs, or independent on-call delivery. The existing disposable lab remains separate. No existing application, database, tunnel, firewall or host daemon needs to be reconfigured.

## Release and isolation contract

- Deploy only the reviewed full commit SHA after CI passes, using `compose.yaml` plus `compose.hardened.yaml` and project **`homelab-sre-prod`**.
- Keep source releases, tools, private secrets, state and backups in an application-owned directory. Do not overwrite another checkout or use another project's volumes/networks.
- Use a private Compose installation/config directory if the shared server lacks Compose. Do not restart Docker, change socket permissions, add users to privileged groups, install global packages or prune Docker resources for this deployment.
- Keep host exporters disabled. The deployment helper rejects active profiles and explicitly clears inherited profile settings.
- Choose unused loopback ports after inspecting listeners. Suggested ports: API `18088`, Prometheus `19090`, Alertmanager `19093`, Grafana `3000`. Abort on collision rather than stopping the existing listener.
- Preserve a baseline of existing container IDs and `State.StartedAt` values. Compare it after rollout/recovery; never restart another project to make room.

## Prepare a source-bound image

Build the static binary from the clean reviewed checkout on the build machine, not on the shared server:

```bash
mkdir -p bin
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
  -ldflags='-s -w -buildid=' -o bin/reliability-api ./cmd/reliability-api
```

Use `GOARCH=arm64` for a reviewed ARM64 target. The current runtime CI validates AMD64. Transfer the tracked release files and binary to a new immutable release directory; verify a SHA-256 transfer checksum. Never transfer `.env`, provider credentials or another project's data.

On the deployment host, build only the small runtime image:

```bash
docker build -f Dockerfile.runtime --build-arg "SOURCE_REVISION=$SRE_IMAGE_TAG" \
  -t "homelab-sre-observability/demo-api:$SRE_IMAGE_TAG" .
```

`SRE_IMAGE_TAG` must be the full 40-character reviewed commit SHA. The helper checks the image revision label. `Dockerfile.runtime` uses the same non-root static-service runtime and health check as the source-build Dockerfile; compilers and dependency downloads stay off the shared host. CI builds both paths and exercises the runtime image.

## Private file-backed secrets

Use a new directory outside the release checkout. Example, with `SRE_SECRETS_DIR` set to that application-private path:

```bash
(
  set -euC  # subshell, fail closed, and never clobber existing files
  umask 077
  mkdir -p "$SRE_SECRETS_DIR"
  chmod 0700 "$SRE_SECRETS_DIR"
  test ! -e "$SRE_SECRETS_DIR/grafana_password"
  test ! -e "$SRE_SECRETS_DIR/receiver_token"
  openssl rand -hex 32 > "$SRE_SECRETS_DIR/grafana_password"
  openssl rand -hex 32 > "$SRE_SECRETS_DIR/receiver_token"
  chmod 0444 "$SRE_SECRETS_DIR/grafana_password" "$SRE_SECRETS_DIR/receiver_token"
)
```

Run generation **only for new files**; do not overwrite existing credentials during routine deployment. Individual files are read-only/readable by the non-root containers; the host directory is private. Compose local secrets are file mounts, not encrypted secret-manager storage. Back up/manage those secrets separately; never commit or log their values.

Set `GRAFANA_ADMIN_USER` to the intended bootstrap account. Set `GRAFANA_ADMIN_PASSWORD=file-managed-placeholder` only to satisfy interpolation of the lab base file: the hardened overlay removes that password from the container and uses `GF_SECURITY_ADMIN_PASSWORD__FILE`. Actual credentials come from the generated file. Grafana bootstrap variables do not rotate an already initialized database account.

## Preflight, rollout and verification

Set the reviewed image tag, private secret directory and the four chosen `SRE_*_PORT` variables, then:

```bash
./scripts/deploy-local.sh
```

The helper validates the resolved model before creating containers. It requires disabled lab controls, source-bound images, private file secrets, loopback ports, bounded resources/logs, no privilege additions or host namespaces, no Docker socket/root mounts, and project-owned volumes/networks. It blocks Prometheus lifecycle/admin mutation flags. It never deletes volumes or prunes other Docker resources.

After readiness, verify:

1. API, Prometheus, Alertmanager and Grafana readiness.
2. `/work?fail=true` returns 403; readiness injection and the API's lab receiver are absent.
3. The separate authenticated receiver is scraped, and `Watchdog` notifications arrive there.
4. Black-box targets are successful and 28-day compliance is absent during warm-up.
5. The original containers' IDs/start times match the saved baseline.

Use SSH forwarding for UIs rather than opening firewall/tunnel ports, for example:

```bash
ssh -N -L 3000:127.0.0.1:3000 -L 19090:127.0.0.1:19090 approved-host
```

## Backup and isolated restore verification

The first recovery gate is an explicit cold backup of **only this project's** three named volumes:

```bash
./scripts/backup-stack.sh --offline /application-private-path/backups
```

This declares a maintenance gap, stops only `homelab-sre-prod`, archives each project-labeled volume, computes checksums, extracts into fresh disposable restore volumes, and verifies every regular file's hash. Temporary restore volumes are removed, and the original stack is started again even on backup failure. It never restores over live volumes. Utility containers are network-isolated/resource-limited; temporary DAC/ownership capabilities are required solely to archive/restore this project's mixed-UID data.

Keep archives private: Grafana state can contain sensitive data. A file-content restore drill is **not** a full application recovery/RTO test. Arrange encrypted off-host copies, a tested full service restore, measured RPO/RTO and a backup schedule before accepting production recovery requirements. The existing backup-freshness exporter is separate; do not point it at other applications without their owner's approval.

## Rollback and production acceptance

Retain prior source/binary/image versions. Roll back only this project's release/image after checking storage compatibility; never use `down --volumes` as rollback. The first installation has no previous SRE release—on failure preserve evidence and stop only the new project rather than improvising changes to another workload.

The receiver is isolated from the demo process but still shares the Docker host. Production paging requires an independently operated destination and external missing-heartbeat detection; local Watchdog delivery does not detect power/router/host loss. Before claiming production acceptance, also review identity/TLS requirements, resource headroom under real load, off-host recovery, and the actual 28-day observation/maintenance policy. New deployment is not historical SLO evidence.
