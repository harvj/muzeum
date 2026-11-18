# First P1.3a live provider pilot

Run on 2026-11-17 (America/Chicago) at `4bda71bc8090b8daf45f417ad70e9e84a776b591` with `recording-evidence-v1`. The single-surface smoke test completed through Solid Queue and persisted usable responses from both live adapters. Three additional surfaces completed in the bounded evaluation. All four assessments abstained. Zero suggestions were emitted, so suggestion precision is undefined.

## Run and controls

A fresh PostgreSQL cluster listened only on a private Unix socket. Rails verified separate `pilot_primary` and `pilot_queue` connections. The Discogs adapter accepted the protected operator configuration and successfully parsed authenticated search results. The worker consumed only the resolution queue, with recurring jobs disabled. The public-catalog test cases were constructed as Last.fm-shaped observations in two disposable archives. No production export was needed. The populated source MBIDs in the table are deliberately supplied test inputs, so the run cannot estimate the availability or reliability of claims in real Last.fm data.

| Pilot | Selected | Completed | MusicBrainz | Discogs | Failures | Abstentions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 · Smoke | 1 | 1 | 3 | 1 | 0 | 1 |
| 2 · Evaluation | 3 | 3 | 5 | 2 | 0 | 3 |
| Total | 4 | 4 | 8 | 3 | 0 | 4 |

Counts are durable provider reservations. All work finished with zero failed attempts and zero resolution decisions. The evaluation reused the Roygbiv search across two surfaces within the same pilot. App requests used the existing spacing, caching, leases and durable due times. No production systems or existing listener assignments were accessed.

## Catalog comparison

All inputs credit Boards of Canada. For the two album cases, the source edition claim was `c77121b6-4552-3127-9f19-685a7f8f090f`. The independent tracklist checks used the artist's release and the MusicBrainz public release and recording pages. The public Discogs release page could not be fetched in the independent documentation browser. MusicBrainz cross-links Discogs release [1354](https://www.discogs.com/release/1354) and master [1893](https://www.discogs.com/master/1893). Those cross-links are separate from the worker's results. [Artist album tracklist](https://boardsofcanada.bandcamp.com/album/music-has-the-right-to-children) · [MusicBrainz UK CD edition](https://musicbrainz.org/release/c77121b6-4552-3127-9f19-685a7f8f090f)

| Case | Independent catalog label | Muzeum evidence and abstention |
| --- | --- | --- |
| Smoke · Music Has the Right to Children / Roygbiv | The official album contains the 2:31 recording at CD position 10. [Recording](https://musicbrainz.org/recording/2a72cd7b-f566-4c91-8e9b-7b33b95dfff7) | Confirmed claim and slot in MusicBrainz. Search returned 18 candidates including the claim. Reasons `competing_recordings`, `incomplete_discogs_evidence`. |
| Evaluation · Music Has the Right to Children / Kaini Industries | The album and supplied CD identify the 0:59 recording at position 8. [Recording](https://musicbrainz.org/recording/f12fd639-90f1-4149-a113-5f1c3c09505e) | Confirmed claim and slot. Three search candidates include two with the exact title and one titled “Kaini Industries (We Are Your Friends rework).” Reasons `competing_recordings`, `incomplete_discogs_evidence`. |
| Evaluation · Peel Session / Roygbiv | Conflicting album context. The checked original EP and Warp reissue omit this track. [Original EP](https://musicbrainz.org/release/0709c446-e190-4dce-b469-908e51267770) · [Warp reissue tracklist](https://bleep.com/release/141387-boards-of-canada-peel-session?lang=en_GB) | Verified the supplied Roygbiv recording claim and found it in search. No matching edition slot. Reasons `competing_recordings`, `unverified_edition_slot`, `incomplete_discogs_evidence`. |
| Evaluation · Missing album / Roygbiv | The official cut is a plausible candidate. The surface alone leaves the performance unresolved. [Recording and appearances](https://musicbrainz.org/recording/2a72cd7b-f566-4c91-8e9b-7b33b95dfff7) | Found the same 18 candidates. No source track claim or album context. Reasons `missing_album`, `missing_source_mbid`, `unverified_recording`. Discogs status `no_album_context`. |

MusicBrainz and Discogs produced zero explicit contradictions. The Peel Session input conflicts with the independently checked catalog. Discogs searches were incomplete for all three album-bearing inputs. The album query returned 52 results across 3 pages in each pilot and the EP query returned 26 across 2 pages. The worker stopped at page one under the current rule, before any Discogs release-detail request. This run therefore did not exercise live Discogs track-list corroboration, contradiction or country/year comparisons. The report retains derived counts and cross-references. Data provided by [Discogs](https://www.discogs.com/).

## MusicBrainz candidate identities

IDs are listed in the order returned by the search. The Roygbiv list applies to all three Roygbiv surfaces.

- **Kaini Industries** · `f12fd639-90f1-4149-a113-5f1c3c09505e`, `576d25d0-039c-4afd-9385-3ba84cc52789`, `f70d1184-3fe3-41bf-a8ae-ed4a15e91317`.
- **Roygbiv** · `1a8f24d1-19eb-4988-96b7-b82ead82b0a3`, `aa71149f-73be-48d2-8ccf-83c76d6d4fe7`, `e7c4d766-26a0-4e8b-b89e-5c8c431f6c8e`, `0eed7321-8df2-499b-903e-a443d0f03a09`, `874060fd-9cd9-4019-ae66-bfb3548fe1da`, `cd148377-1fd5-4577-b7eb-cb89ca371d85`, `cdd58e5b-4fbf-4553-a166-3a5cb5295947`, `4ea6b978-726a-4c65-834b-296947ba466e`, `2a72cd7b-f566-4c91-8e9b-7b33b95dfff7`, `463a92dd-4eed-4bb9-b9e6-1be0d5acf5df`, `b039f909-8f9d-49a0-8f5d-ab978f061855`, `611f526d-7639-4419-b08e-591103e900c0`, `5fa680e0-bc49-4b68-b525-a62f06341c78`, `9e6cad8b-2222-4359-a03a-764c319b924a`, `e9f77c0c-de26-4099-9360-7d29eb48e3c1`, `0f9aafb8-5795-40cc-bb8e-cc38e10ebb17`, `6f752723-dee1-4e02-b6e2-08e3365b9ab2`, `31193151-e1d5-4a22-9cd5-d584d551376d`.

## Findings and open questions

- **Diagnostic defect.** Discogs `incomplete` conflates pagination, multiple exact results and unverifiable release details. The pager metadata distinguishes the observed multi-page cases while the projected request cache is fresh. The durable assessment alone gives reviewers no reason or candidate release references for this outcome.
- **Open — Edition evidence.** Decide whether to preserve a bounded set of edition references and the specific incomplete reason in assessments. Review how multiple editions could support recording identity before adjusting pagination or selection.
- **Open — Competing recordings.** Review whether to distinguish alternatives supported by the observed edition from versions found elsewhere. The current rule blocked a catalog-supported album case even with a verified slot. Two same-title candidates and a named rework illustrate why alternative candidates still need review.
- The focused offline resolution suite passed with 21 examples and zero failures. No evaluator changes were made. The small single-artist sample establishes live adapter connectivity and observed abstention behavior. Automatic acceptance and P1.3b remain subject to separate review.

## P1.3a.1 follow-up · bounded pagination and explanations

The follow-up used `recording-evidence-v2` through the normal Solid Queue worker on November 17, 2026 (America/Chicago). The sample comprised 12 manually constructed Last.fm-shaped surfaces across six artists, with four cases repeated from the first pilot. Catalog expectations were selected before running the worker using the public edition and recording pages and independent artist or label tracklists where available. The sample includes exact album slots, competing recordings, missing album or MBID, an incorrect MBID, conflicting album context, version text, and Japanese artist credit. It contains no listener history.

| Outcome | Count |
| --- | ---: |
| Surfaces selected and completed | 12 |
| Correct suggestions against the pre-labeled catalog | 1 |
| Incorrect suggestions | 0 |
| Abstentions | 11 |
| Final incomplete investigations | 6 |
| Mixed Discogs edition evidence | 1 |
| Complete Discogs contradictions | 0 |
| MusicBrainz / Discogs request reservations | 28 / 26 |
| Transient failures recovered / terminal work failures | 6 / 0 |
| Resolution decisions | 0 |

All six final incomplete investigations hit the Discogs release-detail limit, and one also hit the page limit. The single suggestion is correct for the labeled MusicBrainz edition and track slot. Discogs returned an empty exact search for that surface. One suggestion in a curated, claim-seeded sample provides little evidence about real-world suggestion precision or coverage.

### Surface-level comparison

The MusicBrainz column gives search candidate counts. The Discogs column describes exact artist/album hits under the pilot rule; an empty result does not establish catalog absence.

| Artist and surface | Independent catalog label | MusicBrainz and final outcome | Discogs comparison |
| --- | --- | --- | --- |
| Boards of Canada · Music Has the Right to Children / Roygbiv | UK CD slot 10 identifies the 2:31 album recording. [Edition](https://musicbrainz.org/release/c77121b6-4552-3127-9f19-685a7f8f090f) | 18. Verified claimed slot. Abstained for competing recordings. | All 3 pages, 0 exact hits. |
| Boards of Canada · Music Has the Right to Children / Kaini Industries | UK CD slot 8 identifies the album recording. [Artist tracklist](https://boardsofcanada.bandcamp.com/album/music-has-the-right-to-children) | 3. Verified claimed slot. Abstained for competing recordings. | Same 3 pages, 0 exact hits. |
| Boards of Canada · Peel Session / Roygbiv | The original edition and reissue omit Roygbiv. [Original edition](https://musicbrainz.org/release/0709c446-e190-4dce-b469-908e51267770) · [Reissue](https://bleep.com/release/141387-boards-of-canada-peel-session?lang=en_GB) | 18. Verified the recording claim. Abstained for competing recordings and a missing edition slot. | Both pages, 0 exact hits. |
| Boards of Canada · Roygbiv, album and MBID missing | The album recording is plausible. The observation does not identify the version. [Recording](https://musicbrainz.org/recording/2a72cd7b-f566-4c91-8e9b-7b33b95dfff7) | 18. Abstained for missing album and source MBID. | No album context. |
| Slint · Spiderland / Good Morning, Captain | Original vinyl slot B3 identifies the studio recording. [Edition](https://musicbrainz.org/release/a16b871f-3b71-3bb0-9a9d-798b513a4fc0) · [Artist tracklist](https://slint.bandcamp.com/album/spiderland) | 11. Verified claimed slot. Abstained for competing recordings and incomplete Discogs evidence. | Both pages; 39 exact hits. All 3 checked editions corroborated B3. |
| Slint · Spiderland / Breadcrumb Trail, MBID from Good Morning, Captain | Slot A1 points to `8971961f-143b-4aba-8721-550eeb56073d`, a different recording from the source claim. [Edition](https://musicbrainz.org/release/a16b871f-3b71-3bb0-9a9d-798b513a4fc0) | 10. Abstained for identity conflict, missing search confirmation and edition slot, competition, and incomplete Discogs evidence. | Both pages; 39 exact hits. All 3 checked editions corroborated the title at A1. |
| Nick Drake · Pink Moon / Horn | CD track 5 links to `e2471abf-b272-431f-a030-48a958aa3694`. [Edition](https://musicbrainz.org/release/2a274c12-8785-351a-9155-1d6d2dfde21c) · [Label tracklist](https://nickdrake.islandrecords.co.uk/collections/music/products/pink-moon-cd?currency=USD) | 1. Verified claimed slot. Abstained solely for incomplete Discogs evidence. | 3 of 4 pages; 69 exact hits examined. All 3 checked editions corroborated the track. |
| Nick Drake · Horn, album missing | The claim identifies the recording. The surface omits edition context. [Recording](https://musicbrainz.org/recording/e2471abf-b272-431f-a030-48a958aa3694) | 1. Verified claim. Abstained for missing album and slot evidence. | No album context. |
| The Postal Service · Give Up / Recycled Air | Original edition slot 5 identifies the album recording. [Edition](https://musicbrainz.org/release/15166868-2c9e-36c4-959f-d0010ecf55c0) · [Artist tracklist](https://thepostalservice.bandcamp.com/album/give-up) | 11. Verified claimed slot. Abstained for competing recordings and incomplete Discogs evidence. | Both pages; 36 exact hits. All 3 checked editions corroborated the album track. |
| The Postal Service · Give Up / Recycled Air (Live), MBID missing | The artist's album tracklist gives Recycled Air without the live qualifier. No live recording was assigned as ground truth. [Artist tracklist](https://thepostalservice.bandcamp.com/album/give-up) | 0. Abstained for missing source MBID and incomplete Discogs evidence. | All 3 checked editions lacked the exact live title. Remaining exact hits were unchecked. |
| Broadcast · Tender Buttons / Corporeal | MusicBrainz track 6 and the artist list identify Corporeal on the album. [Edition](https://musicbrainz.org/release/111349e0-5427-4dfb-b419-e2e689861ebf) · [Artist tracklist](https://broadcast.bandcamp.com/album/tender-buttons) | 3. Verified claimed slot. Abstained for competing recordings, incomplete evidence, and mixed Discogs edition results. | 13 exact hits on one page. Releases `532524` and `15640374` corroborated the track. Release `31651739` lacked the exact title. |
| フィッシュマンズ · LONG SEASON / LONG SEASON 1 | The checked SHM-CD edition links track 1 to `2fe61028-0845-46e0-8b6c-e0ed01b76802`. [Edition](https://musicbrainz.org/release/0e81f608-23ca-4d63-9563-9ef7da624ef1) · [Separate SHM-CD reissue listing with the same first track](https://www.universal-music.co.jp/fishmans/products/upcy-7175/) | 1. Verified exact artist credit, recording and slot. Suggested the labeled MBID. | Search returned zero results for the supplied Japanese credit and title. |

The worker checked 12 distinct Discogs release IDs and reused them across compatible catalog queries. The first pilot's Boards of Canada album query now completes all 3 pages. It returns zero exact artist/album display-string matches despite the independently cataloged edition, exposing a limitation of exact Discogs text comparison. The six transient failures were MusicBrainz HTTP 503 responses. They produced scoped partial assessments, recovered through durable retries, and left all 12 work items complete. The final evaluator reproduced all 12 completed assessments offline from the captured projections. Country/year differences across editions were retained as context and excluded from recording disagreement counts. Data provided by [Discogs](https://www.discogs.com/).

### Review questions

- **Open — Discogs discovery.** Evaluate bounded exact-title alternatives and provider cross-references for casing, localized credits, and equivalent editions. A completed query with zero exact hits supports only that query outcome.
- **Open — Edition evidence.** Decide how verified corroboration should affect eligibility when additional editions remain behind the cap. Horn illustrates the trade-off. The incomplete-evidence veto remains in force.
- **Open — Candidate relevance.** Review whether an alternate recording from a different edition should block a verified slot in the observed edition. The current competing-recordings rule remains in force.
- A broader, independently labeled archive-shaped sample is still needed for automatic acceptance review. The follow-up used one protected local worker and disposable primary and queue databases. It produced no listener decisions.
