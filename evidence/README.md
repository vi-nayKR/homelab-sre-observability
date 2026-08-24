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
