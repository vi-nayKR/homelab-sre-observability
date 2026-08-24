# Limitations and Unproven Claims

## Architecture limits

- Prometheus, Grafana and Alertmanager each have one instance.
- The Docker host, its disk, home router, ISP and power are failure domains.
- Laptop sleep/off time can stop both observation and the observed service.
- The default alert webhook shares the demo service failure domain.
- The stack has local disk retention and no remote-write durability.
- Default black-box probes originate from the same Docker host, not a separate region.

## Measurement limits

- The dashboard's p95 is a short-window operational signal, not a full SLO calculation.
- A 15-day Prometheus retention ceiling cannot prove a 28-day objective without remote storage or exported records.
- Synthetic probes do not capture all user workflows or client-side failures.
- No load benchmark is included yet, and no throughput number should be inferred.
- A source-level rule test proves expression behavior on fixtures, not real incident detection.

## Security limits

- Failure controls have no authentication and are suitable only behind loopback/private lab boundaries.
- Grafana uses a locally managed static admin password; production would require stronger identity and rotation.
- TLS is not configured for loopback UIs.
- Docker socket and privileged cAdvisor access are deliberately absent from the default stack.

## Claims not permitted from this repository alone

- “Achieved 99.5% availability.”
- “Reduced MTTR.”
- “Production-grade high availability.”
- “PagerDuty/on-call experience.”
- “Multi-region monitoring.”
- “Handles N requests per second.”

Replace a limitation only when the repository contains reproducible evidence and the README is updated in the same commit.
