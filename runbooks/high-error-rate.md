# Runbook: High HTTP Server-Error Ratio

## User symptom

More than 5% of observed demo requests return 5xx over five minutes and the condition persists for five minutes.

## Triage

1. Confirm total request rate; a ratio at near-zero traffic may be statistically weak.
2. Break errors down only by bounded `route` and `method` labels.
3. Check p95 latency and in-flight requests for saturation.
4. Review structured logs for the affected route and time window.
5. Identify whether controlled error injection is active.

Queries:

```promql
sum by (route) (rate(sre_demo_http_requests_total{status_class="5xx"}[5m]))
sre_demo:http_errors:ratio_rate5m
sre_demo:http_request_duration_seconds:p95_rate5m
sre_demo_http_requests_in_flight
```

## Mitigation

For the game day, stop the generator:

```bash
make stop-errors
```

For a real service, prefer the smallest reversible action: remove a bad instance from traffic, roll back the identified change, disable a failing optional dependency or shed noncritical load. Do not make several simultaneous changes that destroy causal evidence.

## Recovery verification

- Failing request generation has stopped.
- Normal `/work` calls return 200.
- The five-minute ratio trends down and the alert resolves.
- Request rate has not fallen to zero and hidden the problem.
- A corrective action is assigned if the incident was not an exercise.

