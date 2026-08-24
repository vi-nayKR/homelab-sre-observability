# Security Boundaries

## Defaults

- Host ports bind only to `127.0.0.1`.
- Containers drop all capabilities and set `no-new-privileges` where compatible.
- The demo image is a static binary in `scratch`, running as UID/GID 65532.
- Configuration mounts are read-only.
- Resource ceilings reduce denial-of-service impact on the lab host.
- `.env` and runtime evidence are ignored by Git.
- Dashboard and target labels must not contain user IDs, tokens, request IDs or private addresses in public commits.

## Secrets

Only the local Grafana bootstrap credential belongs in `.env`. Do not add alert webhook credentials, cloud keys or Medha secrets to Prometheus labels or checked-in configuration. For a real receiver, inject a secret at deployment time from a secret manager or root-readable host file.

## Exporters

Node Exporter reveals host and filesystem metadata. Bind it to a private address and permit only the monitoring host with a host firewall. Do not expose it through Cloudflare public DNS. Avoid Docker socket mounts; they confer sensitive control/metadata access.

## Failure endpoints

`/admin/readiness` and `/work?fail=true` exist to make failure observable. The Compose port is loopback-only. A production service should compile out such controls or require strong authorization and an audited change workflow.

## Dependency updates

Dependabot proposes updates, but operators must review release notes, image provenance, configuration changes and rollback. Updating a tag without testing the alert path is not routine maintenance.

## Reporting

This is a personal lab. Do not file public issues containing private hostnames, IP addresses, logs, access tokens or customer data. Rotate any credential immediately if it is committed, then remove it from history; deleting the latest line is not sufficient.

