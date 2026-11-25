# Issue 28 acceptance

Production baseline is published v0.7.2. This candidate is intended for disposable qualification. It requires no migration.

| Requirement | Evidence |
| --- | --- |
| Listener-scoped resolution coverage | Read-only effective-ledger count on v0.7.2. 290 of 293,126 assigned (0.099%) and 292,836 unresolved, across 51,995 distinct unresolved artist/title groups. All 290 assigned observations have a verified canonical release membership. That membership provides no per-play edition attribution. |
| Adaptive recall | Bounded additional recording queries run only after existing discovery cannot establish a credible candidate. The request, accepted IDs, and interpretation are retained. The real Dionysus replay still discovers the short movement and preserves the seven-track source edition. The qualifier replay proves candidate recovery and deliberate abstention under simulated provider results. |
| Queue | Counts effective unresolved observations including individual exceptions. Status joins use the claims of the observation linked from the row. Desktop and mobile browser coverage exercises the review link and confirmation. A bounded read-only EXPLAIN ANALYZE of the exact new query, including queue status joins, took 1.57 seconds at production cardinality. The prior ranking-only plan took 2.06 seconds. These are database measurements and do not establish end-to-end or tail latency. |
| Safe background batch | The runner enqueues at most ten investigations per invocation, scans at most three ranked pages and returns a continuation cursor. It refuses production and uses existing authorization, durable jobs, provider budgets, cache, and retry behavior. Its test verifies priority, repeat invocation, reuse, and absence of observation and canonical changes. |
| Review and learning | Decisions reference the immutable assessment and include the decision-time ranking, shortlist, selection and adaptive search paths. The disposable shadow report checks chronological and identity-disjoint partitions and compares only recorded searches. Unattempted searches remain unevaluable. Selection agreement measures preference, rather than objective recording accuracy. |
| Representative evaluation | Independent blinded labels are outstanding. The versioned retained holdout is suitable for fixed regression checks only. It surfaced 7 of 10 identifiable cases, ranked 3 first and 7 in the top three, and issued two false-positive recommendations in 13 cases. |
| Manual ID and canonical assignment | Routine review remains select and confirm. The manual recording-ID form is removed. Internal exact-ID lookups remain available and the batch does not write assignments. |
| Publication and closure | Production acceptance, separate deployment authorization and publication are outstanding. Issue #28 remains open. |

## Reproduction

- Run the existing Rails suite and the Chrome suite with `BROWSER_TESTS=1`.
- Run `bin/rails runner script/resolution_real_corpus.rb` in a disposable environment to replay the retained holdout.
- Run `bin/rails runner script/resolution_investigation_batch.rb LISTENER_ID LIMIT [BEFORE_COUNT BEFORE_ID]` in a disposable environment with the worker enabled. Keep the returned cursor if continuing the scan. Restart from the head to pick up changed priorities.
- Use `script/resolution_manual_review_learning.rb` in a disposable environment. Its shadow outcomes have no production ranking effect.

## Independent label protocol

Sample by impact before scoring. Keep the benchmark read-only and retain the sampling seed, claim snapshot, evaluator revision, and provider fixture digests. Reviewers do not see candidate ordering or recommendations. They record supported MusicBrainz identity, ambiguity, or unavailable evidence with sources. Disagreements require adjudication before scoring. Keep challenge cases separate from the prevalence estimate and report recall and recommendation metrics with their denominators by stratum. A label for an ambiguous case must not force a single recording.
