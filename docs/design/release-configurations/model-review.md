# Release configuration model review

## Why this changes the schema contract

Today a canonical `Release` has one operative track sequence.
`CatalogTrackSlot.base_sequence` means `edition_mbid IS NULL`; any non-null
edition MBID is treated as an additional appearance. Base slots feed listening
membership and totals. `CanonicalCatalog::Store` rejects a different program
for an admitted group unless the operator performs a base correction, which
replaces the old base slots and records their history in a catalog revision.
Storing alternative fully operative sequences in those rows would either
treat base tracks as bonus appearances or add tracks to current totals
without an admission decision.

[REL-014 and REL-016](../../domain/release-assignment.md) currently specify
one authentic representative sequence. Preserve that sequence as the
admitted listening base while adding separately reviewable configurations.
The policy needs to state how a preferred configuration relates to that base
before the mutation path is implemented.

## Proposed additive design

1. Add `release_configurations` under the existing canonical `Release`. Each
   entry references its exact MusicBrainz edition and stores an immutable
   ordered source-track snapshot and digest. Each slot carries medium,
   position, track MBID, source recording MBID, credited text and reported
   length. Reuse exact-sequence comparisons and retain independent source
   editions for corroboration. A new source snapshot creates a revision and
   never overwrites the reviewed snapshot.
2. Add append-only listener-scoped `release_configuration_decisions` with
   actor/listener, parent release, selected configuration, predecessor, and
   evidence reference. Enforce that the configuration belongs to the
   parent. A missing preference falls back to the current reviewed base.
   Preferred configuration initially changes presentation only. It does
   not replace membership, alter release listening inclusion, or assert
   per-play edition credit. Correcting the admitted listening base remains
   a separate explicit operation.
3. Store bounded adjacent-program assessments in the existing evidence
   ledger. Reuse the exact-recording MusicBrainz and linked Wikimedia
   fetchers. Fetch the specific release's complete tracklist only when its
   appearance warrants review. Keep alternate configurations, evidence-only
   appearances, and independent original programs visibly distinct.
4. Reuse the existing `Release` row and transactional admission path for an
   independently issued program where supported. Preserve source evidence,
   verify the preview against the latest assessment at confirmation, reuse
   canonical recording identities, and stop after the selected program.
   A same-group sibling needs distinct program evidence and a deliberately
   selected edition; the existing conflicting-group guard must never be
   bypassed implicitly. Record a confirmed relationship and its source
   evidence with the admission revision. The evidence and defer actions do
   not create canonical releases.

No existing recording or release IDs need to change. The initial migration
adds empty tables and indexes, with no production backfill, slot rewrite,
or accounting change. For existing releases, the current reviewed base
remains the fallback and can supply a configuration snapshot when an
operator opens review. A missing complete source snapshot stays pending
rather than reconstructing unverified positions from titles. The pre-change
application can continue reading the established base during a compatible
operational recovery. The deployment still requires reviewed additive
migrations and the existing backup and four-database recovery controls.

## Acceptance after model review

Exercise one matching-surface recording confirmation while provenance is
pending. Existing per-observation overrides keep precedence. Then verify
that selecting UK, September US, or 1991 Japan configuration creates no
recording decision or listening change. Verify separate explicit admission
of a fully checked single, and verify that selecting an anniversary
configuration does not append bonus material to the admitted album.
Show the dated US discrepancy and provider gaps without inferring audio
equivalence or edition played. Qualification binds Rails and Chrome
regressions, responsive screenshots, exact-SHA CI and the existing signed
Shell checks to the eventual implementation candidate.

**Open decision for review.** Approve the additive model and confirm that
“preferred configuration” should change the displayed configuration only,
with a separate explicit operation to change admitted listening membership.
