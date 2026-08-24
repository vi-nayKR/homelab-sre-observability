# Evidence Directory

`runtime/` is ignored because it may contain host-specific data. Publish only sanitized, reviewed artifacts.

For every game day create a dated directory containing:

```text
metadata.md             commit, host, architecture, versions, time zone
timeline.md             UTC events and decisions
queries/                Prometheus API output before/during/after
alerts/                 firing and resolved Alertmanager output
logs/                   minimal redacted excerpts
screenshots/            optional supporting views
postmortem.md           completed review
verification.txt        validation and corrective-action result
```

Never publish environment files, cookies, Authorization headers, private addresses, access URLs containing tokens, database rows or unredacted logs.

## Accepted alert game-day run

- commit: `8a8b319445533d1600c25590db848ab2c4557cba`
- workflow: [run 32764397577](https://github.com/vi-nayKR/homelab-sre-observability/actions/runs/32764397577)
- workflow window: 2026-08-24 18:47–18:56 UTC
- exercise window: 2026-08-24 18:49:10–18:56:54 UTC
- environment: GitHub-hosted `ubuntu-latest` AMD64 Linux runner; one ephemeral Docker Compose host
- result: source/config/rule validation passed; readiness returned 503 while liveness remained 200; the black-box probe changed from 1 to 0; `BlackboxProbeFailed` completed its two-minute hold; Alertmanager routed it; the receiver recorded one alert-specific firing webhook; readiness and the probe recovered; Prometheus cleared the firing series; the receiver recorded one alert-specific resolved webhook
- retained raw evidence: short-lived workflow artifact containing before/during/after Prometheus queries, Prometheus firing state, active Alertmanager state, bounded webhook counters and UTC metadata

The preceding run `32762274785` proved firing delivery but failed because its generic 200-second poll window was shorter than Alertmanager's configured five-minute group interval for the resolved notification. Commit `435ddb7` made that lifecycle wait explicitly bounded at 400 seconds. Commit `8a8b319` then added a bounded alert-name label so the final run proves the `BlackboxProbeFailed` webhook specifically rather than only receiver-wide traffic. See the [completed postmortem](../postmortems/2026-08-24-readiness-alert-lifecycle.md).

This evidence proves one controlled lifecycle on one ephemeral host. It does not establish an availability percentage, production scale, external paging delivery, professional on-call experience or a real-world recovery-time objective.
