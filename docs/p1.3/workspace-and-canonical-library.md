# P1.3b recording resolution and canonical library

Artists, Releases, Recordings, and Resolution are authenticated navigation destinations. The library is shared canonical catalog data. Listening activity and recording decisions are computed for the current OIDC listener and their active archive grants. Library pages link from release track positions to the recording's resolved listening history. A recording may have zero resolved observations. Unresolved listens are outside that count, and listening activity is unavailable without a connected archive.

## Resolution

Browse exact archive surfaces by stable keyset. Filters cover unresolved or resolved surface defaults, candidate suggestions, conflicting evidence, and current one-observation exceptions. The first matching observation is the stable surface reference. Imported Last.fm observations appear without any catalog pre-processing. An explicit provider check investigates one selected observation and its claim group. It uses the same shared request spacing and cooldowns as P1.3a.

The detail page shows original artist, album, and track text, count, source MBID claims, provider evidence, current assignment and earlier assessments and decisions. Candidate cards distinguish verified observed-edition slots from other catalog appearances. A uniquely supported exact edition slot can be suggested for manual review even when the evidence has other uncertainties. Checked Discogs editions can corroborate the track independently of overall completeness. For the workspace, Discogs discovery uses verified MusicBrainz edition cross-links and matches artist and release-title variations limited to capitalization and whitespace. It retains the three-page and three-detail ceilings, explicit incompleteness and contradictions. Discogs catalog payloads stay behind the projected cache. The page presents derived historical comparison summaries and source attribution.

- **Apply to all** appends a listener-scoped surface decision. Existing and future exact matching observations inherit it unless their individual decision takes precedence.
- **Only this time** appends an individual exception for the selected immutable scrobble.
- **Leave unresolved** explicitly masks lower-precedence evidence. **Return to inheritance** appends an inherit entry at the selected scope.
- Writes require the current decision head and recheck authorization in the ledger transaction. Rejected stale writes ask the listener to review the current state. Another listener's decisions and reasons remain private, including on a shared archive.

## Admission and refresh

A recording choice comes from an assessment for the authorized exact surface. The candidate's MusicBrainz identity is available immediately, and a durable catalog import request is committed with the append-only decision. The worker verifies that recording directly and imports its credited artist identities before attempting release enrichment. A release failure leaves the decision intact.

Automatic **catalog admission** requires an exact observed album title, an official edition independently verified to contain the selected recording, and edition chronology consistent with the release group's first release. The worker inspects at most three MusicBrainz editions. It prefers a qualifying album to a same-context single or EP, and admits a qualifying original single or EP when the observed context supports it. A title alone supplies no release authority. Live, compilation, or other unusual editions require deliberate selection in this implementation. Multiple defensible, materially different collections or conflicting Discogs edition evidence leave the release association pending. A missing album or inadequate edition evidence leaves a pending association. A country-of-origin chronology fallback is still open. Where available, bounded Discogs comparison is retained alongside MusicBrainz track-slot evidence.

A listener can choose a specific edition among the selected recording's provider-linked appearances, including deliberately admitting an eligible compilation or live release. **Verify selected release** applies the choice to an already-resolved recording without rewriting its listener decision. The worker still verifies that the edition includes the recording and has a complete supported listing. The first admission fixes the ordered listing used for navigation. Within an established MusicBrainz group, another edition shares that canonical release only when title, credited artist IDs, and ordered recording sequence also agree. Group identity alone is insufficient. Prior releases with the exact edition MBID reuse their existing Muzeum IDs and keep earlier relationships for historical compatibility.

The import includes the admitted edition's recordings and their credited artists, including repeated recording appearances and recordings with zero scrobbles. It makes no provider requests for other appearances of those tracks or the artists' catalogs. The resource ceiling is 200 track slots in one admitted edition. Structured incomplete status covers listings that exceed the ceiling, missing positions or credits, and special layouts such as pregaps or separate data tracks. Catalog membership creates zero scrobbles and zero per-play credited releases.

The **Import** action refreshes the entity shown. A recording refresh compares recording metadata without picking a release. Use the workspace to retry a contextual admission or select another release. A release refresh verifies its admitted edition and keeps the existing listing if ordered membership has changed, pending review. A refreshing entity has one active durable request per kind. An incompatible concurrent release choice is reported so it can be resubmitted after the active request completes.

| Metadata | Use | Refresh behavior |
| --- | --- | --- |
| MusicBrainz artist and recording IDs, artist name/country, recording title/duration | Stable linking, display, search, duration context | Fill absent fields and update previously verified values. Retain separately curated or legacy conflicts and record incoming evidence. |
| Ordered credited artist IDs, credited names and join phrases | Navigation and attribution | Add missing links. Preserve previous links and positions when provider credits change. Retain the current provider credit in revision evidence for review. |
| MusicBrainz edition/group references, collection title/type, partial date and country | Admission provenance and catalog display | Compare the verified edition's supported fields. Missing fields preserve stored values. Another equivalent edition contributes evidence without replacing the admitted edition's display metadata. |
| Medium, track position/number, provider track ID, displayed title and recording ID | Complete ordered navigation, including repeated recordings | A bounded transaction writes a complete new listing. Membership/order changes surface as incomplete on refresh. Earlier slot display labels remain stable. |
| Provider request timestamps, projection hashes, derived Discogs comparisons, field changes and conflicts | Audit and manual review | Append catalog revisions. Short-lived projected request cache supports durable retries without repeating successful requests. |

## Running and recovery

For a disposable environment, use separate primary and Solid Queue database URLs with the [P1.3 queue setup](README.md#running-the-bounded-pilot). Set `MUZEUM_CATALOG_WORKER=1` explicitly for the development web and job processes. The opt-in queue worker consumes `canonical_catalog` alongside configured local queues. With protected Discogs credentials absent, workspace assessments record incomplete Discogs evidence and remain reviewable.

Requests use one database lease, a 32-request ceiling and five provider failure attempts. Retry-After and shared cooldowns determine due times. A queue handoff failure leaves durable work visible. Reopen the entity and use Import or run `bin/rails canonical_catalog:dispatch` to enqueue up to 25 due or lease-expired requests. No recurring task is enabled. Production catalog queue consumption requires a separate operator activation, and the P1.3a pilot remains independently blocked in production.

The migration adds three empty tables, two nullable columns on releases and append-only revision guards. It ran against a pre-migration PostgreSQL database populated with 10,000 immutable scrobbles, fingerprints, legacy surface and membership rows, canonical identities, and a listener ledger entry. Original-column digests matched before and after. The [exact-hash manifest](../../config/deploy/migrations.json) records the additive review. A separate PostgreSQL 16 and Restic rehearsal passed all 28 backup helper tests and 32 deployment tests, including isolated four-database recovery. A disposable Solid Queue worker consumed a recording job through stubbed MusicBrainz HTTP with two provider requests, imported all three ordered track slots across two discs, and produced zero listener decisions. The full Rails suite passed with browser tests enabled. Browser coverage exercises keyboard submission, record and release navigation, zero-listening presentation, and desktop/mobile light and dark layouts. Production migration, recovery and activation remain subject to the operator [deployment workflow](../deployment/workflow.md).

### Production catalog activation and rollback

Obtain explicit authorization for activation, the two Muzeum service restarts and the scoped smoke test. Before changing the flag, verify the published revision, both Muzeum services, public `/up`, fresh Solid Queue heartbeats and recent Last.fm job completions. Check the primary database for active catalog requests and the queue database for existing catalog jobs. Reconcile any unexpected work before activation. Verify the Discogs application pair through an authenticated catalog search and install it through the [protected credential mechanism](providers-and-verification.md#protected-credential-setup). The production file is owned by `muzeum` with mode `0600`. Keep credentials out of terminal output, command arguments and logs.

Run the read-only [readiness probe](../../ops/catalog/readiness.py) from reviewed operator tooling on the production host. Use the exact reviewed file without deploying it into the application release or installing a privileged helper. Coordinate the window with the existing Muzeum deployment, backup and shared infrastructure locks. Confirm no retained active deployment or conflicting operation before editing or restarting. Capture a UTC baseline and run the probe with `--catalog off` before activation.

Add exactly one `MUZEUM_CATALOG_WORKER=1` entry in the protected environment file. Preserve the other settings, ownership and mode. Restart the worker first while the existing web process continues serving requests with catalog dispatch paused. Once the worker passes readiness, restart web to load the flag for request dispatch and paused-state messaging.

```sh
sudoedit /var/www/muzeum/shared/.env
sudo systemctl restart muzeum-worker.service
worker_started=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)
sudo /usr/bin/python3 /path/to/reviewed/readiness.py --catalog on --since "$worker_started"
```

Continue only after that probe passes.

```sh
sudo systemctl restart muzeum-web.service
web_started=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)
sudo /usr/bin/python3 /path/to/reviewed/readiness.py --catalog on --since "$web_started"
```

The probe reports systemd process state and PID separately from public HTTP, the current supervisor's exact queue subscription and one-thread pool, its four Solid Queue heartbeats and Last.fm completions. It reports unfinished and failed ingestion counts for comparison with the baseline. A passing probe requires a new imports completion since the supplied UTC marker. The 45-second polling budget covers the observed roughly four-second startup with margin for boot and scheduling variability. Individual probes time out within four seconds, and heartbeat ages allow 90 seconds for Solid Queue's 60-second heartbeat cadence. The existing ready jobs in `solid_queue_recurring` are outside the worker subscription. Watch imports completions and backlog throughout the smoke test because catalog uses the same worker thread.

The flag also permits user-requested workspace assessments. Those can append evidence and suggestions. Automatic recording decisions and per-play release attribution stay disabled. The separately configured P1.3a resolution pilot remains blocked in production. Catalog has no recurring dispatch. A request has a renewable two-minute lease, a combined 32-call provider ceiling and up to five counted failures. Provider reservations are paced at one second for MusicBrainz and three seconds for Discogs. Shared cooldown deferrals do not consume failure attempts.

For the initial smoke test, use an authorized archive observation for Boards of Canada's “Roygbiv” ([recording MBID `2a72cd7b-f566-4c91-8e9b-7b33b95dfff7`](https://musicbrainz.org/recording/2a72cd7b-f566-4c91-8e9b-7b33b95dfff7)) and explicitly select the [original UK CD of *Music Has the Right to Children*](https://musicbrainz.org/release/c77121b6-4552-3127-9f19-685a7f8f090f) (edition MBID `c77121b6-4552-3127-9f19-685a7f8f090f`). If a recording assignment is needed, use **Only this time** and account for the resulting manual decision. Track only this candidate and edition through the workflow. Verify exactly one admitted release with all 17 ordered slots, “Roygbiv” at medium 1, position 10, and catalog provenance for the edition. Verify that the import has no additional release admissions, scrobble writes, per-play release credits or automatic recording decisions. Allow for independent Last.fm arrivals when comparing source rows. Record incomplete or failed provider evidence and preserve the request for review. Skip bulk dispatch during the smoke test.

If either stage fails, preserve its output and remove the added flag with `sudoedit /var/www/muzeum/shared/.env`. If web already restarted with the flag, restart web first to stop new web dispatches. If activation stopped at the worker stage, leave the original web process running. Restart the worker, capture a fresh UTC marker, and run the same probe with `--catalog off`.

```sh
sudoedit /var/www/muzeum/shared/.env
# Run this web restart only if web loaded the enabled flag.
sudo systemctl restart muzeum-web.service
sudo systemctl restart muzeum-worker.service
rollback_started=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)
sudo /usr/bin/python3 /path/to/reviewed/readiness.py --catalog off --since "$rollback_started"
```

Confirm both units and `/up` are healthy, the worker advertises exactly `imports,default`, and imports completions continue. Preserve durable catalog requests, queue records, catalog revisions, admitted releases and listener decisions. Inspect pending or leased work before any subsequent activation or targeted retry.

The first production attempt on November 19 UTC is documented in the [readiness incident record](catalog-activation-2026-11-19.md).

## Open questions

- How to rank alternatives when multiple verified original editions share a title but have different track sequences.
- Whether documented artist-origin evidence is reliable enough for a chronology fallback when the Last.fm album is missing.
- How to review recording redirects, changed track slots and revised credit order without silently replacing a canonical interpretation.
- How to expand candidate discovery for localized names and missing artist/title without weakening exact user surface identity.
- Larger-archive workspace reads currently group the authorized archive on demand. Measure latency before adding a maintained projection.
