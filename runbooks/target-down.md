# Runbook: Target Down or Black-Box Probe Failure

## User symptom

Prometheus cannot scrape the service or the external HTTP probe does not return the expected success response.

## Immediate checks

1. Confirm whether `up{job="demo-api"}` or `probe_success{job="blackbox-http"}` failed. Do not assume they mean the same path.
2. Check the Alertmanager start time and affected `instance`, `service` and `environment` labels.
3. From the observer, run a bounded verbose request to the exact probe target.
4. Check Docker service state and recent logs.
5. If metrics scrape succeeds but the probe fails, inspect readiness state and the application response.
6. If both fail, inspect process/container state, port binding, name resolution and host resources.

Local commands:

```bash
curl --verbose --max-time 5 http://127.0.0.1:8080/health/ready
curl --fail --max-time 5 http://127.0.0.1:9090/-/ready
docker compose ps
docker compose logs --since 10m demo-api blackbox-exporter prometheus
```

## Mitigation

- For the deliberate readiness exercise: `make restore-readiness`.
- For a bad local release: identify the last-known-good image/commit, stop new change activity and roll back through the documented deployment path.
- Do not repeatedly restart a live process when only a dependency/readiness check is failing.

## Recovery verification

- Direct readiness returns 200.
- `up` and `probe_success` return 1 for at least two scrape intervals.
- The alert resolves in Alertmanager.
- Error and latency signals return to baseline.
- Record recovery time and whether any telemetry gap occurred.

## Escalation

Escalate when recovery requires changing data, credentials, network policy or a live Medha node. Create a change record and identify backup/rollback before proceeding.

