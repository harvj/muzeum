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

## Approved semantics

The operator approved two additive tables and subsequently corrected the
preference contract. The earlier display-only proposal is superseded.

- A shared immutable snapshot preserves an exact official source edition,
  ordered positions, recording MBIDs, credits, lengths, provenance, and the
  reported date at source precision.
- Append-only listener decisions choose a verified snapshot or revert to the
  admitted base. The choice determines display, release listening membership,
  and the effective date used by catalog date queries. It never changes the
  shared historical publication date, recording decisions, or edition credit.
- Releases with no preference keep their current base and additional-track
  listening behavior. There is no migration backfill or slot rewrite.
- Independent adjacent admission uses explicit catalog review. Same-group
  sibling admission still requires evidence of a distinct musical program and
  must preserve the conflicting-group guard.
