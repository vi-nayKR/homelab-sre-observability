# Architecture and Signal Flow

## User and telemetry paths

The demo request path is `client → demo-api`. The white-box metrics path is `Prometheus → demo-api:/metrics`. The black-box path is `Prometheus → blackbox exporter → demo-api:/health/ready`. These paths answer different questions:

- `up` says Prometheus can scrape the metrics endpoint.
- `probe_success` says an HTTP user path returns the expected response.
- application metrics explain rate, status class, latency and concurrency inside the service.
- structured logs retain individual events without turning request-specific values into metric labels.

An available metrics endpoint does not prove the user path works. A working user probe does not reveal an approaching resource ceiling. Both are required.

## Label policy

Allowed application labels are bounded:

```text
method: GET, POST, PUT, PATCH, DELETE, OTHER
route: constants registered in source
status_class: 2xx, 3xx, 4xx, 5xx
```

Raw URL paths, query parameters, request IDs, users, IP addresses and error messages are prohibited metric labels. They belong in carefully redacted logs or traces. This prevents unbounded time-series growth and accidental sensitive-data collection.

## Liveness versus readiness

- Liveness answers whether the process is capable of making progress. It does not call dependencies.
- Readiness answers whether the instance should receive traffic. The lab can set it false while liveness stays true.
- Startup is represented by Docker's health-check start period; the Kubernetes project will add an explicit startup probe.

Restarting a live process because a database is temporarily unavailable can amplify an incident. Orchestrators should remove a not-ready instance from traffic and reserve liveness restart for unrecoverable process failure.

## Alert path

Prometheus evaluates recording and alerting rules every 15 seconds. Alertmanager groups by alert name, service and environment, inhibits lower-signal demo alerts when the service target itself is down, and posts firing/resolved lab notifications to `/alerts`.

The in-service receiver is deliberately a demonstrator, not a production design. A real receiver must remain available when the monitored service fails.

## Storage and resource controls

- Prometheus retention: 15 days and 4 GB.
- Named volumes hold Prometheus, Alertmanager and Grafana state.
- Component memory and CPU limits prevent the lab from exhausting an 8 GiB monitoring laptop.
- Containers drop Linux capabilities and disallow privilege escalation where supported.
- Host ports bind to loopback.

## Extension path

1. Add private-LAN node exporters with a firewall allowlist.
2. Export backup last-success timestamp through Node Exporter's textfile collector.
3. Add Grafana Alloy and Loki with redaction and short retention.
4. Instrument a disposable Go dependency with OpenTelemetry.
5. Only then propose minimal Medha API instrumentation through its normal review/deploy path.

