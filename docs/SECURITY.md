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

The disposable lab uses a local Grafana bootstrap credential in `.env`. The hardened overlay uses file-backed Grafana and webhook secrets from a private directory outside the checkout. It rejects placeholders and never logs secret contents. Do not add webhook credentials, cloud keys or existing application secrets to labels/configuration. Compose local secrets are ordinary file mounts, not encrypted storage; use a managed secret store where the operating environment requires one.

## Exporters

Node Exporter reveals host and filesystem metadata. Bind it to a private address and permit only the monitoring host with a host firewall. Do not expose it through Cloudflare public DNS. Avoid Docker socket mounts; they confer sensitive control/metadata access.

## Failure endpoints

`/admin/readiness` and `/work?fail=true` are available only when `LAB_CONTROLS_ENABLED=true`; the binary default is false, and the hardened overlay forces false. Delay injection is also disabled. The hardened API has no lab receiver; a separate receiver requires a mounted bearer token and accepts one bounded JSON payload. Keep every published port on loopback and use SSH forwarding. The deployment gate forbids host namespaces, privilege additions, Docker socket/root mounts, inherited profiles and cross-project volumes/networks.

## Dependency updates

Dependabot proposes updates, but operators must review release notes, image provenance, configuration changes and rollback. Updating a tag without testing the alert path is not routine maintenance.

## Reporting

This is a personal lab. Do not file public issues containing private hostnames, IP addresses, logs, access tokens or customer data. Rotate any credential immediately if it is committed, then remove it from history; deleting the latest line is not sufficient.
