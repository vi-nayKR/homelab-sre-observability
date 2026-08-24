# Runbook: High p95 Request Latency

## User symptom

Five-minute p95 latency exceeds 500 ms for ten minutes.

## Triage

1. Confirm the affected route and request rate.
2. Compare p50/p95/p99 from histogram buckets rather than averaging percentiles.
3. Check in-flight requests and host CPU, memory, I/O and network saturation.
4. Look for error-ratio changes, retries and dependency timeouts.
5. Compare with the last deployment/change timestamp.

In the game day, query whether `delay_ms` traffic is active. In a real service, never add request URLs or query strings as metric labels to answer this question; use redacted structured logs or traces.

## Mitigation and verification

Stop the controlled slow load or roll back the causally identified change. Verify normal requests, p95 recovery over two evaluation windows, stable error rate and no hidden request-rate collapse.

