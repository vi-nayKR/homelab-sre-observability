# Game Day: Error Spike and Readiness Failure

## Objective

Prove that the stack detects user-visible errors, routes an actionable alert, supports diagnosis from metrics/logs, and records recovery. This exercise does not prove real-world MTTR or availability.

## Safety and scope

- Run only against the local demo service.
- Confirm every published port binds to `127.0.0.1`.
- Do not point failure scripts at Medha or any third-party endpoint.
- Do not alter Prometheus data during the exercise.

## Preflight

Record the Git commit, host architecture and timestamps in `evidence/runtime/`.

```bash
make validate
make up
make status
curl -fsS 'http://127.0.0.1:8080/work'
```

Confirm Prometheus targets are up and no unexpected alert is firing.

## Exercise A — high server-error ratio

Start controlled failing requests:

```bash
make inject-errors
```

Observe:

- `rate(sre_demo_http_requests_total{status_class="5xx"}[5m])`;
- `sre_demo:http_errors:ratio_rate5m`;
- pending then firing `DemoHighErrorRatio` after its five-minute hold;
- the Alertmanager group and webhook log.

Follow [runbooks/high-error-rate.md](../runbooks/high-error-rate.md). Mitigate:

```bash
make stop-errors
```

Verify the ratio falls and the alert resolves after the window/hold behavior.

## Exercise B — readiness without process death

```bash
make fail-readiness
curl -i http://127.0.0.1:8080/health/ready
curl -i http://127.0.0.1:8080/health/live
```

Expected: readiness is 503, liveness is 200, the metrics scrape remains up and the black-box probe fails. Restore:

```bash
make restore-readiness
```

## Evidence to retain

- UTC start/detection/acknowledgment/mitigation/recovery times;
- Prometheus query output before, during and after;
- Alertmanager firing and resolved payload or API output;
- exact commands and unexpected behavior;
- one screenshot linked to the raw series, if useful;
- a completed postmortem copied from `postmortems/TEMPLATE.md`;
- the commit containing one tested corrective action.

## Cleanup

```bash
make stop-errors || true
make restore-readiness || true
make down
```

Do not delete the named telemetry volumes until evidence has been exported and reviewed.

