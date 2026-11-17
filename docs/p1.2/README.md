# P1.2 — ready for deployment approval

Implementation is complete locally and pushed; **production is unchanged and deployment is not authorized by this report**. The existing production archive remains 292,852 observations on application revision `ab314224abb9be1b28b01c953fe093c4bddf2e72`.

Implementation commit: `1ca96bcafa10f17b2b010699b2e02252f746c50e`. [Implementation CI passed all four jobs](https://github.com/harvj/muzeum/actions/runs/44111097002). A final documentation/evidence commit follows; obtain its exact candidate with `git rev-parse HEAD` and use its CI before approving deployment.

| Completion condition | Evidence |
| --- | --- |
| Existing observations intact | [Read-only production audit](coverage.md): 292,852 distinct tuples, 1,465 matching raw checksums, complete recorded page range/checkpoint. Independent populated-migration/backfill digests unchanged for 250k synthetic IDs, original payloads, raw pages, principals and checkpoints |
| Completed scrobbles import automatically | Durable Solid Queue dispatcher, shared request budget/account grants and serialization, bounded overlapping windows, fixed-bound drift replay, retry/circuit-breaker state and permission checks; no browser or canonical provider dependency |
| Open dashboard updates without refresh | Authenticated version checks and Turbo Stream replacements; real Chrome test commits a new source page and observes the count update without reload |
| Interrupted imports recover | Atomic page/delivery/checkpoint, separately committed fetch receipt, lock contention, precommit failure/postcommit acknowledgment loss, queue-lease and source-checkpoint restart tests; no duplicated source events |
| Auth/application isolation intact | Existing OIDC SSO/session/logout/CSRF/state/nonce/PKCE/denied-flow browser tests pass; no Auth/CE deployment, credentials, cookies or authorization mechanism changed |
| Backup/restore works | Existing production schedules/receipts inspected read-only. New encrypted **synthetic local** Restic integrity/restore, four table-fingerprint sets, remapped read-only application boot, identity and session decryption verified |

[Schema/provenance/scheduler design](architecture.md), [all measured results and limitations](performance.md), [fault matrix](fault-matrix.md), [migration/backup/rollback approval packet](deployment-readiness.md).

**133 Rails/browser examples pass** on PostgreSQL 16, including all existing authentication cases and responsive light/dark layouts. **28 backup helper tests pass**. RuboCop: no offenses; Brakeman: no warnings; refreshed dependency audit: no vulnerabilities. Zeitwerk, production asset compilation and migration replay pass. Retained logs are under [verification](verification/).

The diagnostic statement budget is exceeded and the bulk write proposal is narrowly missed in some trials; all timings remain recorded. Neither has shown a material reliability/resource issue. The actual end-to-end 250k import/replay and memory/lookup gates pass. At 10,000 distinct sources, hours of lag under one request/second are an explicit provider-capacity constraint. No further scheduler optimization is required for P1.2 acceptance under the operator clarification.

Remaining source uncertainty includes indistinguishable same-second repeats, same-total upstream edits/deletions/omissions and delayed changes older than the overlapping lookback. Matching Last.fm's profile playcount is not a completeness proof. Historical gaps/errors not retained by P1.1 cannot be invented retrospectively.

Approval must cover the additive primary-schema cutover, bounded legacy-provenance indexing, Muzeum-only maintenance and subsequent synchronization activation. A fresh encrypted production backup and matching four-database restore are required **before** production changes, and again after promotion. Keep synchronization/public writes off until source preservation/provenance checks pass. The previous P1.1 source authorization is not a functional P1.2 rollback: use compatible forward repair or the guarded Muzeum-only withdrawal, preserving all data.

P1.3 timeline browsing and automatic timeline insertion are documented future contracts only. No Now Playing, MusicBrainz/Discogs/Spotify integration, canonical resolution or derived listening aggregates were introduced.
