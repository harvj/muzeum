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
