# Public profiles and administrative ownership

[Issue #30](https://github.com/harvj/muzeum/issues/30) delivers the public
homepage and the first read-only profile path before [resolution issue #28](https://github.com/harvj/muzeum/issues/28).

## Behavior and access

- `/` is public. Last.fm onboarding is visibly disabled. The featured link is
  present only when the `qalephd` profile passes publication checks.
- `/archive` is the private dashboard. Eligible top-level navigation to it
  uses the existing guarded OIDC entry. Auth continues to own login and
  assurance. The Auth application link to `/` lands on the new public
  homepage, from which **Open your archive** enters the private dashboard.
- `/profiles/:profile` and its catalog routes are read-only. They can resume an
  existing Muzeum session to display Profile while keeping all catalog queries
  scoped to the published profile. The archive pages by observation time and ID
  and displays only timestamps and catalog or reported display fields.
  Unresolved titles carry an explicit label. Private settings, import
  status, decision history, raw fetches and payload provenance stay private.
- The public catalog starts with the owner's effective resolved plays
  in the published archive. It includes verified admitted releases that
  contain those recordings, their complete track listings, and relevant
  artist credits. Navigation remains scoped to that set. Unplayed tracks
  have zero plays. Membership does not create observations or release
  credit. The catalog and archive are served from local data. HTTP no-store
  and Turbo cache opt-out protect later reads after withdrawal.
- Existing source grants remain archive access and are separate from profile
  ownership. For an administratively owned archive, resolution writes and
  manual archive management require that owner and an active grant. Existing
  private grants and historic interpretations remain intact. Typing the username
  cannot add a new grant to an administratively owned archive. Legacy archives
  without an owner record retain existing grant-based management. Catalog
  import requires a managed archive grant. Public routes expose no writes.

## Production evidence and prerequisites

Read-only production inspection found archive ID **1**, storage user ID **1**,
and an enabled existing Auth issuer/subject identity with one active grant for
the archive. The legacy username agreed. All **292,969** observations and
**713** import runs observed at inspection pointed to the same storage user.
No authentication material or raw production observations were copied. This
supports an administrative association after the operator confirms the identity.
It is not verification by Last.fm.

The migration adds one empty table and an archive/exact-surface expression index for catalog discovery. A unique archive index prevents duplicate
ownership, and establishment checks the existing archive user and active grant.
Publication state is separate from administrative ownership. An additive
migration creates the append-only publication event table and installs a grant
trigger. It does not backfill approvals or change existing profile or source
rows. An already-private profile stays private. Activation requires a consent
event recorded through the new workflow. A username reconciliation, owner
disablement or grant revocation withholds the public endpoints. Revoking or
removing the owning grant clears activation in the same transaction, even when
the grant is changed outside Rails. Restoring a grant requires explicit
reactivation with a reviewed provider reference. Self-service controls are deferred.

### Last.fm publication and retention review

Last.fm API terms §2.7 specifies attribution, profile and catalog link targets,
placement approval, and prior written approval of public pages using its web
services. §4.2 extends credit and applicable license notices and privacy
obligations to public reuse. Whether serving stored observations without live
API calls changes the written approval requirement is open. Resolve attribution,
links, notices and approval against the exact public scope before activation.
[Last.fm API terms](https://www.last.fm/api/tos)

§4.3.4 states a 100 MB aggregate usage cap, prior written consent for a larger
portion, and caching consistent with response headers. The measured raw-body
inventory of 324,374,400 bytes exceeds that threshold if counted. The
83,055,438-byte normalized observation measurement is a different representation.
The handling of raw bodies, normalized fields, caches, backups and duplicates
requires confirmation. Limiting the public projection leaves the retention
question open.

All imported observations, including the existing 292,969, are permanent.
Preserve original timestamps, reported artist, recording and album text, and
source provenance. Canonical resolution adds interpretation. The retained raw
HTTP responses are a separate dataset. This work neither alters them nor
authorizes future changes. Account-holder-initiated export uploads are the likely
initial onboarding path, with optional incremental Last.fm API synchronization
using the associated source username subject to separate review.

A reviewed alternative contractual interpretation belongs in a separate
protected decision record with its reviewer, terms version, affected data and
routes, reasoning, conditions and review date. Keep it out of
`provider_approval_reference`, which is for actual provider approval. Accepting
an alternative would require an explicit DOM-020 policy revision and a distinct,
validated authorization basis in the application. The existing gate explicitly
requires provider approval.

### Operator sequence

1. Verify exact-SHA CI and the migration hash. With separate deployment
   authorization, use the [guarded deployment](../../deployment/workflow.md)
   with Muzeum quiescence, a fresh encrypted backup and isolated four-database
   recovery. Verify the private profile remains undiscoverable and returns 404.
   Preserve the audit table on forward repair.
2. Re-read the existing administrative association, Auth-linked owner and active
   grant privately. For an archive with no ownership row, establish it only
   with separate authorization using
   `bin/rails 'listening_profiles:establish[1,1,<reviewed-ownership-reference>]'`.
3. With consent-recording authorization, use the protected Muzeum runtime to run
   `bin/rails 'listening_profiles:record_consent[1,1]'`. Supply the private
   `MUZEUM_PUBLICATION_EVIDENCE_REFERENCE` through the protected runtime
   environment. The referenced record identifies the owner, scope, approval
   and operator. Verify the consent timestamp and audit event while the public
   key and provider reference remain null for the private profile.
4. After separately authorizing activation, provide an evidence reference to
   actual written Last.fm approval via the same protected environment variable
   and run `bin/rails 'listening_profiles:activate[1]'`. Verify the homepage,
   archive and catalog routes anonymously, and check that protected reads and
   writes are still denied.
5. To withdraw, provide a protected withdrawal evidence reference and run
   `bin/rails 'listening_profiles:withdraw[1]'`. This clears the active key,
   current consent and current provider reference while retaining ownership and
   all prior events. Verify the homepage link disappears and public routes return
   404. Explicit reactivation after manual withdrawal requires new consent.

These tasks have no web endpoints. Repeating the same consent or activation
against the same state preserves the original evidence. Repeating withdrawal on
a fully withdrawn row is a no-op. Inspect audit evidence privately and keep
protected references and identifiers out of issue updates.

## Verification

All 219 local examples passed with browser tests enabled. RuboCop, Brakeman,
Zeitwerk, and a fresh PostgreSQL migration replay passed.

Chromium used disposable fixture records and the normal Site Art image layer
with bundled texture bytes. The profile label in the screenshots identifies
synthetic history. No production observations were used.

| View | Desktop light, 1440 × 960 | Mobile dark, 390 × 844 |
| --- | --- | --- |
| Homepage | [Capture](screenshots/landing-light.webp) | [Capture](screenshots/landing-dark.webp) |
| Profile archive | [Capture](screenshots/archive-light.webp) | [Capture](screenshots/archive-dark.webp) |

A warmed local request probe used 293,000 synthetic observations plus two
fixture plays and one resolved surface. Seven timed requests gave medians
of 3.4 ms for the archive and 3.7 ms for the recordings index with the
exact-surface index. The catalog median was 411 ms before the indexed lookup.
These are local measurements for a sparsely resolved archive.
