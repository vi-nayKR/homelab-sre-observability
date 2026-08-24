# Postmortem: Readiness Alert Lifecycle Verification

Status: final  
Date/time zone: 2026-08-24 UTC  
Author/reviewer: Vinay KR  
Severity: controlled lab exercise; no real-user incident

## Summary

A controlled readiness failure kept the demo process live while its user-path probe failed. `BlackboxProbeFailed` completed a real two-minute hold, reached Alertmanager and delivered a firing webhook. The first end-to-end verifier then timed out before the resolved webhook because its generic 200-second polling window was shorter than the configured five-minute Alertmanager group interval. The service had already recovered; the failure was in lifecycle verification. The verifier now gives only the resolved transition a 400-second bound, and the receiver records a bounded alert name. The accepted rerun proved one firing and one resolved webhook specifically for `BlackboxProbeFailed`.

## Impact

- affected journey: the disposable demo readiness endpoint and local black-box probe;
- observed behavior: readiness returned 503 while liveness and the metrics scrape remained healthy;
- real users/data/security: none;
- request impact: not quantified, because the exercise intentionally held readiness down rather than generating a representative workload;
- error-budget impact: no real service objective was consumed; the 99.5% objective is a lab target, not measured availability.

## Detection

Prometheus observed `probe_success{job="blackbox-http"} == 0`. After the two-minute hold, `ALERTS{alertname="BlackboxProbeFailed",alertstate="firing"}` appeared, Alertmanager exposed the active routed alert, and the local receiver recorded its firing webhook. This is symptom-based detection from the user path. It does not test an external paging provider because the lab receiver shares the demo service's failure domain.

## Timeline

| UTC time | Event / observation / decision | Evidence |
| --- | --- | --- |
| 18:26–18:32 | First full-lifecycle run observed and routed the firing alert, then timed out before the resolved webhook | failed run `32762274785`; partial artifact at commit `4d6aa16` |
| 18:35 | The resolved wait was changed from the generic 200-second bound to a 400-second bound that covers the configured five-minute group interval | commit `435ddb7` |
| 18:37–18:44 | Rerun proved receiver-wide firing and resolved delivery | successful run `32763255973` |
| 18:47 | Receiver metrics and smoke assertions were narrowed to a bounded alert name | commit `8a8b319` |
| 18:49:10 | Accepted exercise metadata began after clean-stack readiness | accepted artifact `metadata.txt` |
| 18:51:35 | Alertmanager recorded `BlackboxProbeFailed` active after its two-minute Prometheus hold | accepted artifact `firing-alertmanager.json` |
| 18:51:54 | Verifier had observed Prometheus firing state, Alertmanager routing and the alert-specific firing webhook; it then restored readiness | accepted artifact and script sequence |
| 18:56:54 | Probe recovery, Prometheus resolution and one alert-specific resolved webhook were all verified | accepted artifact `after.json`, `webhook-counts.json`, and `metadata.txt` |

The exact sub-minute probe recovery time after readiness restoration was not written as a separate timestamp. `recovered_utc` marks completion of the full notification lifecycle, not five minutes of continued user-path impact.

## Technical cause

The readiness failure itself was deliberate: the administrative lab endpoint changed readiness to false while leaving liveness true. The unexpected verifier failure came from applying one generic polling bound to two different timing contracts. Prometheus alert evaluation and the two-minute `for` hold completed inside 200 seconds, but Alertmanager's resolved notification remained governed by `group_interval: 5m`. The test treated a configured delay as a missing notification.

A second evidence issue was also found during review: the receiver counter originally labeled only webhook status, so other alert groups could not be distinguished from `BlackboxProbeFailed`. The Alertmanager route groups by alert name, making a bounded alert-name label appropriate and finite.

## Resolution and recovery

The script restored readiness immediately after capturing the firing states. It then verified the next successful black-box probe and absence of the Prometheus firing series. The test-specific correction retained the ordinary 200-second bound for all other waits and used 400 seconds only for resolved webhook delivery. The receiver now normalizes alert names to the seven configured names plus `other`, preventing arbitrary label cardinality.

## What went well

- the initial failure still uploaded its partial artifact, preserving the exact last successful lifecycle stage;
- readiness and liveness were modeled separately, so diagnosis did not confuse process death with traffic eligibility;
- the failed run exposed a configuration/test-contract mismatch rather than being dismissed as CI flakiness;
- the final evidence distinguishes the exact alert from other burn/error alerts generated during the exercise.

## What made diagnosis or recovery harder

- the local Mac had no Docker runtime or `promtool`, so the public AMD64 runner was the runtime reproduction environment;
- Alertmanager's resolution timing is intentionally decoupled from immediate service recovery;
- receiver-wide counters initially made alert attribution weaker than the README wording.

## Corrective actions

| Priority | Action | Owner | Due | Verification | Status |
| --- | --- | --- | --- | --- | --- |
| P1 | Give resolved delivery an explicit bound longer than `group_interval` | Vinay KR | 2026-08-24 | run `32763255973` completed in 9m43s | complete |
| P1 | Retain a bounded alert-name label and assert the exact firing/resolved group | Vinay KR | 2026-08-24 | run `32764397577` records one firing and one resolved `BlackboxProbeFailed` webhook | complete |
| P1 | Upload partial evidence even when the lifecycle verifier fails | Vinay KR | 2026-08-24 | failed run `32762274785` retained its firing-stage artifact | complete |
| P2 | Move the receiver outside the monitored service failure domain | Vinay KR | future lab iteration | external authenticated receiver exercise | open |
| P2 | Repeat the clean runtime on ARM64 | Vinay KR | future lab iteration | equivalent artifact with ARM64 hardware recorded | open |

## Lessons and follow-up

Alert tests must encode both service-state timing and notification-system timing. “The service recovered” and “the resolved notification was delivered” are separate assertions. Public evidence should also identify the exact alert group it claims, while bounding labels so proof does not create a cardinality problem.

Accepted evidence: [workflow run 32764397577](https://github.com/vi-nayKR/homelab-sre-observability/actions/runs/32764397577), commit `8a8b319`.
