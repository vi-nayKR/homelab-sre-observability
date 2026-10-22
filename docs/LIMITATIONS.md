# Limitations and Unproven Claims

## Architecture limits

- Prometheus, Grafana and Alertmanager each have one instance.
- The Docker host, its disk, home router, ISP and power are failure domains.
- Laptop sleep/off time can stop both observation and the observed service.
- The lab webhook shares the demo process. The hardened authenticated receiver is separate from that process, but still shares the host. Independent paging and dead-man detection are not configured by this repository.
- The stack has local disk retention and no remote-write durability.
- Default black-box probes originate from the same Docker host, not a separate region.

## Measurement limits

- The dashboard's p95 is a short-window operational signal, not a full SLO calculation.
- A configured 35-day/8 GB retention ceiling is not historical evidence. Size eviction, observation gaps and rollout warm-up still limit the window; coverage guards and conservative missing-probe accounting make those limits visible.
- Synthetic probes do not capture all user workflows or client-side failures.
- No load benchmark is included yet, and no throughput number should be inferred.
- A source-level rule test proves expression behavior on fixtures, not real incident detection.

## Security limits

- Failure controls are disabled by default and forced off in the hardened deployment; the disposable lab explicitly enables them.
- Grafana uses a file-backed bootstrap password in hardened mode, not enterprise SSO or automated rotation. Compose file secrets are not encrypted secret-manager storage.
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
