# Public profiles and administrative ownership

[Issue #30](https://github.com/harvj/muzeum/issues/30) delivers the public
homepage and the first read-only profile path before [resolution issue #28](https://github.com/harvj/muzeum/issues/28).

## Behavior and access

- `/` is public. Last.fm onboarding is visibly disabled. The featured link is
  present only when the `qalephd` profile passes publication checks.
- `/archive` is the private dashboard. Eligible top-level navigation to it
  uses the existing guarded OIDC entry. Auth continues to own login and
  assurance. The Auth application link to `/` lands on the new public
  homepage, from which **Sign in** enters the private dashboard.
- `/profiles/:profile` and its catalog routes are read-only and do not
  resume an Auth session. The archive pages by observation time and ID
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
No production account is associated or published by migration. Publication is
a separate record of explicit owner consent and a provider approval reference.
Both must be present and tied to the approved username and active owner/grant.
A username reconciliation, owner disablement or grant revocation withholds the
public endpoints. Self-service visibility and revocation are deferred.

### Last.fm publication gate

Last.fm's API terms §2.7 call for prior written approval for public pages using
its web services and specify attribution, link targets and approval of
placements. §4.2 covers license notice, attribution and privacy obligations,
and §4.3.4 lists a 100 MB usage cap and caching requirements. Resolve the terms'
application to this stored archive and proposed public catalog, confirm use and
retention scope with Last.fm, and obtain written approval or document a reviewed
alternative covering publication. Reconcile any required notice, branding or
profile/catalog links before enabling access. Confirm owner approval covers the
displayed timestamps, unresolved text, interpretations and future additions.
No provider branding is introduced by this milestone. [Last.fm API terms](https://www.last.fm/api/tos)

### Proposed operator sequence

1. Review the exact-SHA CI and migration hash. With separate deployment
   authorization, run the [guarded deployment](../../deployment/workflow.md).
   The additive migration requires fresh encrypted backup and isolated
   four-database recovery checks. Verify the new homepage and that the profile
   path returns 404 before association and publication.
2. With separate association authorization, re-read the production identity,
   matching grant and history before running the Muzeum runtime task privately.
   Use the reviewed operator evidence reference and verify publication columns
   are still empty afterward.

   ```sh
   bin/rails 'listening_profiles:establish[1,1,<reviewed-ownership-reference>]'
   ```

3. Obtain the exact owner's approval and satisfy the provider gate. After
   separate publication authorization, use the deployed runtime Rails console.
   Pass the consenting user ID confirmed in the private review and a reference
   to the written provider approval. Verify the exact public archive and catalog
   routes anonymously, and confirm the private routes remain protected.

   ```ruby
   profile = ListeningProfile.find_by!(lastfm_account_id: 1)
   profile.record_publication!(
     consenting_owner: User.find(1),
     provider_reference: "<reviewed-provider-approval-reference>"
   )
   ```

4. If authorized to withdraw publication, clear `owner_consented_at` through
   the existing operator runtime and verify 404 on the public archive and
   catalog. Preserve the ownership row, observations, and decisions.

No production deployment, association or publication occurred during the work.

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
