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

The five-minute p95 remains an operational signal, filtered to successful `/work` requests. Histograms now include bounded `status_class` labels, and the 28-day observed-latency ratio uses successful-request bucket/count increases, not averaged quantiles. It is coverage-gated but cannot establish strict latency compliance for unknown requests during scrape gaps.

## Retention, coverage and unknown observations

Prometheus is configured for 35 days with an 8 GB ceiling. The first limit reached wins; capacity settings alone do not prove retained history. At the fixed 15-second schedule, `sre_sli:availability:coverage_ratio28d` compares observed samples with 161,280 expected probes. If the schedule changes, update this denominator and tests in the same change.

`observed_ratio28d` averages only available samples. The conservative `ratio28d` instead divides successful probes by **all expected probes**, charging missing observations against the error budget, and is absent below 99% coverage. A newly deployed stack must not display a fictional complete-window success. This is a conservative scheduled-probe estimate, not independent proof of real user availability; maintenance is not silently excluded. Dashboard panels use instant queries so a stale previous compliant value is not reused after coverage drops.

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
