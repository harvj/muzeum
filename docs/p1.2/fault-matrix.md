# P1.2 fault matrix

All fixtures and network responses are synthetic. Production was inspected read-only; no second real import was run. Assertions compare actual rows/evidence/checkpoints, including an independently generated 250,000-fingerprint manifest. Browser tests use separate-origin provider fixtures and real signed OIDC token verification; no production credentials are needed.

| Fault/input | Implemented oracle and result |
| --- | --- |
| Clean 250k import / warm replay | Independent ordered fingerprint digest, exact count, zero new replay observations, no Recording/RecordingSurface creation; A/B/C measurements retained separately |
| Repeated/overlapping/reordered pages | Delivery evidence retained; original IDs/payloads and tuple set unchanged; late out-of-order tuples added once |
| Identical entries inside one page | One source tuple, repeat/multiplicity evidence; no invented separate event identity |
| Same second, different tuples; 201-item bucket | 201 observations retained across main and exact-second paginated sweeps; collision issues remain unresolved |
| Changed MBID/loved metadata | First payload/ID unchanged; later item checksums/raw bytes/delivery and metadata-change issues retained |
| Shared account / distinct account | Two users share one archive and schedule; revocation removes only that viewer; different account identities remain separate |
| Username case / rename / conflict | Case-folded association is deterministic; prior names remain reserved; explicit reasoned rename pauses work; conflicting archives never merge |
| Now-playing, undated, malformed date | Original evidence plus excluded classifications; no listening events or epoch-zero timestamps |
| Invalid UTF-8 | Original response bytes preserved in binary fetch evidence; parsing rejected and checkpoint unchanged |
| Empty/malformed XML / error in HTTP 200 | Durable response/issue evidence; no checkpoint advance or false completion |
| Fixed cutoff / delayed completion | Out-of-window items excluded as evidence; overlapping incremental range admits delayed completed events, not Now Playing |
| Changed source totals | Historical drift pauses; incremental drift replays the original fixed interval at most three generations, then requires review |
| Crash before commit / lost acknowledgment after commit | Transaction failure rolls back page/delivery/observation/cursor; postcommit retry preserves observation ID and resumes the committed cursor |
| DB failure after fetched receipt / before checkpoint | Fetch evidence survives; source/page/checkpoint remain atomic. Queue/dispatch recovery uses durable primary state |
| Same-account concurrent writer | Separate PostgreSQL connection holds the source advisory lock; second writer performs no API call/write |
| Different accounts | Independent source locks; one global database request budget bounds request starts |
| Permission revoked before/during work | Rechecked before fetch and inside commit; no unauthorized page commits. Remaining shared grant permits a newly attributed continuation without falsifying old actor history |
| Timeout / HTTP 429 / envelope 11,16,29 / invalid key | Classified errors retain available bodies; Retry-After/global cooldown and durable bounded retry/pause state verified; no key in normalized transport errors |
| Repeated failures | Five rapid attempts enter circuit-breaker pauses; bounded recovery probes persist errors; permanent permission/key failures stop work |
| Incomplete page budget / service restart | One page is one durable work unit; pending run survives; dispatcher lease recovers lost enqueue; page budget never implies completion |
| Direct SQL/bulk update/delete | Database triggers reject original source/evidence mutations, account reassignment and deletion; downstream interpretation links remain separate |
| Auth/session/navigation | Existing SSO, fresh login, invalid/denied callback, state/nonce/PKCE/session continuity, logout and protected routes retained |
| Open dashboard | Committed synthetic page appears without reload via authenticated Turbo Stream; unchanged versions avoid full statistics; revoked membership cannot select another archive |

The OS-level process-kill/network-disconnect timing during an actual PostgreSQL COMMIT is represented by injected before-commit failure and after-commit acknowledgment loss, with actual PostgreSQL transactions and independent row assertions. This is not a claim of exhaustive crash-consistency/model checking. Same-total upstream edits, undocumented endpoint boundary behavior and source omissions cannot be proved away by these tests.

The virtual paced harness initially exposed a sub-microsecond clock-rounding stall. That incomplete synthetic database was retained separately, and the harness now moves past the persisted retry deadline by one millisecond. It is a harness correction, not a change to real production time or database durability. Initial trials remain under `evidence/initial-trial/` and are excluded from final gates.
