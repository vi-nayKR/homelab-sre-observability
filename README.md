# Homelab SRE Observability

[![CI](https://github.com/vi-nayKR/homelab-sre-observability/actions/workflows/ci.yml/badge.svg)](https://github.com/vi-nayKR/homelab-sre-observability/actions/workflows/ci.yml)

A reproducible reliability lab that answers four operator questions:

1. Are users succeeding?
2. How quickly is the error budget being consumed?
3. Does an alert describe an actionable symptom?
4. Can another operator follow a runbook and verify recovery?

A single-host operations project with an explicitly disposable lab profile and a separate hardened deployment path. It includes an instrumented Go service, Prometheus/Grafana/Alertmanager, black-box probes, SLO coverage guards, authenticated receiver isolation, deployment gates and cold-backup/isolated-restore checks. It does not claim HA or achieved availability. Start with the [deployment and recovery guide](docs/OPERATIONS.md).

## What is implemented

- Go 1.27 HTTP service with request count, error class, duration histogram, in-flight gauge and bounded metric labels.
- Distinct `/health/live` and `/health/ready` behavior.
- Fault injection disabled by default in the binary; explicitly enabled only in the disposable lab Compose profile.
- Prometheus 3.14 with 35-day/8 GB retention ceilings, no lifecycle mutation API, and observation-coverage guards.
- File-backed Grafana/webhook secrets, a separately supervised authenticated receiver, bounded logs and source-commit-tagged runtime images.
- Fail-closed single-host deployment preflight and an explicit cold-backup plus disposable-volume file-restore drill.
- Grafana 13.2 with provisioned datasource and SRE overview dashboard.
- Alertmanager 0.34 with grouping, inhibition and resolved notifications.
- Blackbox exporter 0.28 for user-path availability and latency.
- 99.5% **starter objective** with fast/slow multi-window burn-rate alerts. It is a target, not an availability claim.
- Checksum-aware backup freshness metrics for Node Exporter's textfile collector.
- Go, shell, YAML, dashboard, Prometheus rule and Alertmanager configuration validation.
- Exact multi-architecture image digests as inspected on 2026-08-24.

## Architecture

```mermaid
flowchart LR
    load[Controlled requests] --> api[Instrumented Go API]
    prom[Prometheus] -->|scrape /metrics| api
    prom -->|probe request| blackbox[Blackbox exporter]
    blackbox -->|GET /health/ready| api
    prom --> rules[Recording + alert rules]
    rules --> am[Alertmanager]
    am -->|lab webhook| api
    prom --> grafana[Grafana]
    operator[Operator] --> grafana
    operator --> am
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for signal flow and trust boundaries.

## Requirements

- Docker Engine/Desktop with Compose v2
- Go 1.27 for local tests (the container build supplies its own toolchain)
- Bash, `curl`, `jq` and Ruby
- `promtool` and `amtool`, or Docker so validation can use their pinned images

The stack supports ARM64 and AMD64 images. The optional `linux-host` profile is Linux-only.

## Disposable lab quick start

```bash
make bootstrap
# Edit .env and replace the Grafana password.
make validate
make up
make status
```

Open only from the local machine:

| Component | URL |
| --- | --- |
| Demo API | <http://127.0.0.1:8080/> |
| Demo metrics | <http://127.0.0.1:8080/metrics> |
| Prometheus | <http://127.0.0.1:9090/> |
| Alertmanager | <http://127.0.0.1:9093/> |
| Grafana | <http://127.0.0.1:3000/> |

All published host ports bind to loopback. Do not change them to `0.0.0.0` merely for convenience.

## First game day

Read [docs/GAMEDAY.md](docs/GAMEDAY.md) before starting. The short version is:

```bash
make inject-errors
# Observe request/error/latency signals. The error alert has a five-minute hold.
make stop-errors
```

Readiness failure is separate from liveness:

```bash
make fail-readiness
curl -i http://127.0.0.1:8080/health/ready
curl -i http://127.0.0.1:8080/health/live
make restore-readiness
```

The lab explicitly enables unauthenticated game-day controls and binds published ports to loopback. The binary defaults to controls disabled, and the hardened overlay forces them off. Do not deploy the lab profile as a hardened service; use [OPERATIONS.md](docs/OPERATIONS.md).

## Adding homelab targets

1. Deploy an exporter through a reviewed change; never expose its port publicly.
2. Restrict the exporter firewall to the monitoring node.
3. Copy an example target file without publishing real LAN addresses.
4. Reload Prometheus only after `promtool check config` passes.
5. Confirm the `up` and black-box series include the expected stable labels.

For a public HTTP endpoint, copy:

```bash
cp configs/prometheus/targets/medha-public.yml.example \
  configs/prometheus/targets/medha-public.yml
```

Then edit the target and labels. Do not commit private targets.

## Validation

```bash
./scripts/validate.sh
```

The script checks:

- `gofmt`, race-enabled Go tests and `go vet`;
- Bash syntax, optional ShellCheck and backup metric behavior;
- every YAML file and dashboard JSON;
- the full Prometheus configuration;
- Prometheus alert/recording rule tests;
- lab and hardened Alertmanager/Compose configuration, including rejection of insecure deployment models;
- source-build and compiler-free, revision-labeled runtime images when Docker is available;
- the hardened CI fixture: protected controls, authenticated Watchdog delivery, receiver survival across API restart, SLO warm-up, and cold-backup/isolated file-restore verification.
- clean-stack startup, service readiness, metric scraping, injected readiness failure, black-box observation and recovery in CI.
- a real two-minute `BlackboxProbeFailed` hold, Prometheus firing state, Alertmanager routing, firing/resolved webhook delivery, and retained API evidence in CI.

The CI workflow requires the container checks. A local environment without Docker may validate source and telemetry rules, but that is not full runtime proof.

## SLO and alert philosophy

The initial availability objective is 99.5% successful black-box probes over 28 days. This intentionally modest lab target must be revised from measured user needs rather than tightened for appearance. Latency is tracked, with a starter objective that 95% of successful `/work` requests complete within 500 ms.

Pages describe user-visible symptoms or imminent loss of recovery capability. Dashboard-only signals help diagnose causes. See [docs/SLO.md](docs/SLO.md).

## Evidence status

Verified on a clean GitHub-hosted AMD64 Linux runner by CI:

- full Compose resolution and demo image build;
- clean-stack startup for the API, Prometheus, Alertmanager, Grafana and blackbox exporter;
- direct health, white-box scrape and black-box success;
- bounded 5xx metric generation;
- readiness failure while liveness remains healthy;
- black-box observation of failure and recovery;
- `BlackboxProbeFailed` transition to firing, Alertmanager routing, and firing/resolved webhook delivery;
- stack teardown with volumes.

Accepted evidence: [workflow run `32764397577`](https://github.com/vi-nayKR/homelab-sre-observability/actions/runs/32764397577), commit `8a8b319`, with the [completed readiness-alert postmortem](postmortems/2026-08-24-readiness-alert-lifecycle.md).

Do not describe the following as complete until artifacts exist under `evidence/`:

- clean-clone runtime on ARM64;
- a dashboard snapshot backed by raw query output;
- long-window availability or error-budget performance.

## Limitations

- This is a single monitoring stack with no Prometheus/Alertmanager redundancy.
- A laptop that sleeps cannot measure its own absence.
- The lab receiver shares the demo service. The hardened receiver is a separate authenticated container, but still shares the host; independent paging and missing-heartbeat detection remain required for host-loss coverage.
- Local black-box probes do not prove the view from another region or ISP.
- Configured 35-day retention is not proof of 28 days of data: the size cap can evict earlier. Coverage is displayed, warm-up is suppressed, and missing expected probes consume the conservative availability budget.
- No actual availability, MTTR or performance improvement is claimed yet.

See [docs/LIMITATIONS.md](docs/LIMITATIONS.md) and [docs/SECURITY.md](docs/SECURITY.md).
