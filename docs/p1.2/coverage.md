# Production archive coverage

Read-only audit at **2026-11-17 13:58:36 UTC**, production revision `ab314224abb9be1b28b01c953fe093c4bddf2e72`. The audit used one PostgreSQL repeatable-read, read-only transaction through restricted runtime credentials. No Last.fm calls, production imports, row mutations, service changes or backup changes were performed. [Machine-readable evidence](evidence/production-audit.json); reproducible inspector: [audit_archive.rb](../../ops/ingestion/audit_archive.rb).

| Evidence | Result |
| --- | --- |
| Existing observations / distinct exact source fingerprints | 292,852 / 292,852 |
| Existing IDs | 1–292,852; preserved source digest recorded below |
| Original raw pages | 1,465, covering page numbers 1–1,465 without gaps |
| Raw checksum failures | 0 |
| Recorded source total | 292,852 on every captured page |
| Committed checkpoint | Next page 1,466; status completed; inserted 292,852 |
| Last successful recorded page | 2026-11-17 05:40:35 UTC |
| Fixed upper request bound | Unix second 1,794,889,542 |
| Timestamped source items / distinct exact tuples | 292,852 / 292,852 |
| Exact repeat deliveries within captured pages | 0 |
| Malformed, undated, now-playing, above-cutoff items | 0 |
| Missing fingerprints / raw-page references | 0 / 0 |
| Archived fingerprints absent from their first raw page | 0 |
| Differing observations sharing a second | 2,245 observations in 1,041 account/second buckets |
| Current retained error | None; earlier retry/error history was not retained by P1.1 |
| Source immutability | Enabled database triggers on observations and raw pages; function digest retained in audit |

The source-field digest includes existing IDs, original user lineage, UTC timestamps, payload representations, fingerprints and first-page IDs: `6fad7868cb769fb1229fa3149c4a3269c98886b7b0684f800d531d0e1b5c3041`. The ordered raw-page ID/checksum manifest digest is `f007312317f9131b38307578abce20d8aeef9354fd2d5ef8e6e86d21508d44cb`.

This verifies coverage of the **captured provider traversal** and reconciliation with that traversal's own fixed-bound total. It does not establish that Last.fm returned every real listening event. No comparison with today's profile playcount was used as proof. Timestamp-only gaps can represent silence; they cannot establish missing API records. Last.fm supplies no durable event ID. Identical same-second deliveries cannot be distinguished as separate plays, and differing same-second tuples cannot automatically be asserted to be two listens. Same-total upstream edits, deletions or pagination shifts during the original traversal cannot be ruled out retrospectively. Original request latency, item positions as structured fields, prior errors and explicit boundary sweeps were not retained in P1.1; the raw pages permit additive position indexing, not invention of missing historical evidence.

P1.2 adds durable delivery/error/issue evidence and exact-second boundary sweeps for future work. A completed P1.1 checkpoint is mapped to the source account's historical watermark so enabling synchronization starts a bounded incremental interval, **not another full historical import**. The 48-hour lookback captures delayed submissions within that horizon; older changes remain an explicit coverage limit requiring reviewed replay. No source row is deleted when upstream history changes.
