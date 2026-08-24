# Starter Service-Level Objectives

Status: design target; not yet backed by a complete 28-day measurement window.

## User journey

A user or dependent client needs the HTTP service to accept a request and return a valid response within a useful latency. Internal process health is not the user outcome.

## Availability SLI

```text
good events  = black-box probes returning the expected HTTP 200 response
valid events = all scheduled black-box probes, excluding documented maintenance
SLI          = good events / valid events
```

Starter objective: **99.5% over a rolling 28-day window**.

The error budget is 0.5% of valid probes. At a 15-second probe interval, a continuously running observer schedules 161,280 probes over 28 days, allowing about 806 failed probes. This is a model; actual rule evaluation and missed scrapes must be handled explicitly before reporting compliance.

## Latency SLI

```text
good events  = successful /work requests completing in <= 500 ms
valid events = successful /work requests
SLI          = good events / valid events
```

Starter objective: **95% over a rolling 28-day window**.

The dashboard currently shows a five-minute p95. A complete SLO implementation should use histogram bucket counts over the SLO window rather than averaging quantiles.

## Burn alerts

For the 0.5% availability budget:

- fast page: both 1-hour and 5-minute burn rates exceed 14.4x for two minutes;
- persistent ticket: both 6-hour and 30-minute burn rates exceed 6x for fifteen minutes.

These multi-window conditions reduce pages for single scrape blips while detecting both rapid and sustained user impact.

## Error-budget policy for the lab

- A fast-burn page starts an incident exercise immediately when an operator is on duty.
- A single exercise consuming more than 20% of the window budget requires a postmortem.
- When the budget is exhausted, pause feature work in this repository except security/recovery changes until the corrective action is tested.
- Planned exclusions require a timestamped change record; do not silently delete bad data.

## Review questions after 28 days

1. Is the observer itself continuously available?
2. Do synthetic probes match real user paths?
3. Did any alert have no useful human action?
4. Is 99.5% stricter or looser than user need and hardware reality?
5. Are maintenance and observer gaps represented honestly?
6. Does latency need separate objectives by request class?
