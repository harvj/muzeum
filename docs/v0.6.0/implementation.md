# v0.6.0 implementation notes

## P1 Release Construction

On group confirmation, Muzeum can apply a retained construction proposal and save the recording decision in the same transaction. Construction uses complete, original tracklist evidence. The base sequence keeps its ordered slots. Additional verified edition slots keep their own edition, position and date, and count as canonical memberships. Listening queries continue to count distinct observations. A separate Resolve action remains available while evidence is incomplete.

For corrections, review the proposed sequence and date from retained evidence. The existing release ID is preserved. Muzeum rejects stale corrections and retains previous facts in catalog revision history. Additional editions not covered by the reviewed proposal are preserved. A release that already matches the checked proposal needs no correction.

Recording chronology is independently editable with a cited source or a reason the date is unknown. Partial dates and ranges retain their precision. MusicBrainz's first-release claim and specific edition appearance dates are presented separately.

The retained MusicBrainz Guilt Show responses verify the March 2, 2004 US 13-track base and the August 21 Japanese edition with “Like a Man Possessed” in slot 14. MusicBrainz reports June 22 as that recording's first release date. The separately titled six-track Bonus Web Content has the same March date as the album but does not define its original sequence. [MusicBrainz release group](https://musicbrainz.org/release-group/fcd9c6ae-a4a8-3e59-828e-55f6b1a70198)

The schema changes add Musical Identity decision history and edition-specific track slots. Once edition-specific slots have been written, v0.5.1 would read them as base tracks. An application-only rollback to that build therefore needs review before production. Do not automatically reverse the migration over live memberships.

## P2 Musical Identity

Read the Muzeus badge and palette styles and the category-aware graph and play/time bar partials. The Guide uses the original palette and 18-pixel swatches. Muzeum retains original MusicBrainz genre and tag terms at recording, release, and artist scopes when provided in catalog imports, with the canonical identifier and request provenance.

The Stage A snapshot includes 13 recording lookups. Six have recording genres or tags and seven have neither. This is availability in the sampled responses, not classifier coverage. The snapshot also includes release and artist evidence and Wikidata entity responses. Broad electronic terms co-occur with more specific tags such as ambient techno and IDM on Boards of Canada recordings. Red Clay has no recording-level genre tags in its sampled response. A rule that maps every jazz-funk tag to two colors contradicts the operator's Red Clay reference. Preserve the distinction between metadata observations and the user's interpretation.

The bounded trial ran `python3 docs/v0.6.0/compare_color_predictions.py /tmp/muzeum-v060-evidence`. On three held-out recordings the metadata-only rule abstained on all three. An exact mapped-feature comparison reused the Roygbiv reference and predicted Gray for Turquoise Hexagon Sun and Telephasic Workshop. Both share the example's artist and album. Both methods abstained on Red Clay, whose recording response carried no genres. The Gray targets extrapolate an operator reference for this experiment. They are not independently confirmed recording labels. No cross-artist prediction was supported, so the trial does not establish generalization or justify selecting a production classifier.

Each canonical Artist, Release, and Recording has an independent, revisable assignment. An authorized catalog editor can select one or two colors in the Guide, clear the assignment, or justify an exceptional third color. Corrections append a new decision with the editing account, timestamp, and rationale. The form rejects stale edits. Catalog tables use entity badges and neutral foreground-colored bars. Individual charts use the current entity's assignment. The Guide also shows retained MusicBrainz genres and tags where available. The experiment above is historical evidence. Prediction, learning, and coverage targets are deferred.

## P3 Guide

The right-hand Guide uses the existing Remote Gaming modal-drawer interaction as its reference. It describes the palette, canonical release membership, and listening attribution. The initial Help link sits in the footer to preserve Shell header geometry. Sections have direct hash links and the modal returns focus when dismissed.
