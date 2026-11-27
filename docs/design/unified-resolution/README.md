# Unified Resolution review

The Birthday scenario is derived from Resolution observation 293137. Acceptance uses disposable listening observations and retained MusicBrainz snapshots for *Leisure* and its adjacent singles.

## Recording identity findings

| Appearance | Release track | Recording | Reported track duration | Supported interpretation |
| --- | --- | --- | --- | --- |
| [September 24, 1991 US *Leisure*](https://musicbrainz.org/release/d81bfb74-5d2e-4dcf-956f-550cfde5eed5) | [ecc5fef1](https://musicbrainz.org/track/ecc5fef1-6316-3567-bf42-4e6c8301d431) | [f2903d45](https://musicbrainz.org/recording/f2903d45-03c8-4631-a1e1-3d0d33c57cbe) | 203,933 ms | Verified album appearance. Its relationship to the single recording is unresolved. |
| [April 15, 1991 UK single](https://musicbrainz.org/release/ea3df91a-d85f-435c-8c75-c0a5494e662c) | [9d042e09](https://musicbrainz.org/track/9d042e09-ac31-3f1b-b7cb-69dfb4a33253) | [6eb416f2](https://musicbrainz.org/recording/6eb416f2-5649-497a-b36e-2e47c92f366b) | 194,560 ms | Source disambiguation is “single version.” The exact edit or mix is unverified. The recording entity reports 193,960 ms. |
| [Disputed August 26, 1991 US *Leisure*](https://musicbrainz.org/release/dc2c22eb-9e48-4caa-8263-87c4cfe40a1a) | [c7c5334d](https://musicbrainz.org/track/c7c5334d-1c15-45c7-abdb-fa98ad6df7b5) | [35b0f752](https://musicbrainz.org/recording/35b0f752-a764-46dd-a596-a9fb84b1ac96) | 220,000 ms | Variant unresolved. The recording claim remains evidence while the edition is ineligible for admission. |
| [October 1990 UK “She’s So High” single](https://musicbrainz.org/release/b11e8000-f0c2-4277-befb-b125a5edece7) | [2da98cb4](https://musicbrainz.org/track/2da98cb4-c8d0-300d-89a2-6273611fd01f) | [b9168df7](https://musicbrainz.org/recording/b9168df7-5d1d-48e8-9b6a-4762c379569d) | 230,960 ms | The original title contains “(edit).” MusicBrainz also records an edit relationship to [1c14202a](https://musicbrainz.org/recording/1c14202a-2ea7-4aff-bc41-6c97eb8a45e8), which reports 286,173 ms. |

All three “There’s No Other Way” recording IDs link to the [same musical work](https://musicbrainz.org/work/c8d95c0f-981c-3649-b492-f254209d6f39). The September album and UK single share ISRC `GBAYF9100001`. Each also has separate ISRC claims. The disputed recording supplies no ISRC. None of the loaded relationships directly establishes an edit, mix, or equivalence between those three IDs. A shared ISRC and differences in source duration are insufficient to resolve this conflict. Source titles and the raw timings remain intact. The UI floors durations to whole seconds, while MusicBrainz may round them.

## Decision contract

The owner can check several supported configurations and select one primary configuration. The primary is the preference and, for a new album, the admitted base. A pre-existing base stays intact. Independently issued programs can be checked separately. Unchecked and disputed editions remain evidence.

Checkboxes change browser form state only. The server validates the current assessment, the allowable edition IDs, the surface head and the affected count. Recording assignment, selected catalog writes and configuration decisions commit together. A rejected edit leaves the ledger and catalog unchanged. An individual observation override remains in force. Beyond the matching surface, ambiguous listening remains untouched.

Variant descriptions are reviewed metadata keyed by exact source recording MBID. They do not change titles, infer audio equivalence, control admission or affect listening assignment. The work link only organizes related evidence.

## Verification

`BROWSER_TESTS=1 bundle exec rspec spec/system/birthday_release_review_spec.rb spec/requests/resolution_release_review_spec.rb`

The native Auth review uses the established `spec/browser_acceptance/run-muzeum.sh` runner with a sealed disposable artifact and isolated four-database layout.

## Scope

The provisional controls are enabled for source programs with a checked release-review policy, beginning with *Leisure*. Existing unrelated manual catalog workflows remain available. Matching-surface assignment honors older per-observation overrides. A title-only surface with competing candidates requires an explicit recording choice and acknowledgment before submission. The August edition dispute stays visible as provenance.

For a pending selection, the release count describes the expected new admissions and the unmatched track count describes distinct source IDs with no current canonical match. Final identity and duplicate checks run inside the transaction. The preview cannot establish the edition played.

## Exact-candidate acceptance

Source [`61c7a415dac50eebfacf0ccb51ae3efc2710efb6`](https://github.com/harvj/muzeum/commit/61c7a415dac50eebfacf0ccb51ae3efc2710efb6). [Exact-SHA CI](https://github.com/harvj/muzeum/actions/runs/46039717226) · [disposable Capistrano staging](https://github.com/harvj/muzeum/actions/runs/46039720636).

Native Playwright passed all nine steps using disposable Auth password, TOTP and OIDC, with desktop and mobile viewports. It confirmed browser-only checkbox editing, two configurations and one adjacent single in the same preview, submission for all eight Birthday observations, a separate title-only surface with no preselected recording, Evidence navigation, and logout. The Rails request spec covers invalid-selection rollback and replay protection. The review-only fixture and scenario in this evidence branch bind to the sealed application revision through their recorded file digests.

- [Browser result and screenshot hashes](evidence.json)
- [Commit, tree, archive and environment binding](binding.json)
- [Sealed file inventory identity](sealed-identity.json)
- [Sanitized reproducibility manifest](environment.json)
- Desktop · [unselected](desktop-resolution-unselected.png) · [selected](desktop-resolution-selected.png) · [preview](desktop-resolution-preview.png)
- Mobile · [unselected](mobile-resolution-unselected.png) · [selected](mobile-resolution-selected.png) · [preview](mobile-resolution-preview.png)
- Mobile recording comparison · [unselected candidates](mobile-ambiguous-recordings.png) · [disputed source track](mobile-disputed-track-evidence.png)

The account badge is masked. The screenshots use disposable observations; the source research is real provider evidence. The candidate retains the v0.8.1 version file for visual review. No release number was assigned.
