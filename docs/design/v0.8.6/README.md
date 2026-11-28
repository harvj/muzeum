# Release-backed Resolution

## Production diagnosis

The read-only review used the retained Resolution assessments for observations 293209 and 293210 on v0.8.5. The disposable replay preserves the covered surface sizes and provider candidates and uses fabricated listening timestamps.

### Crash

The retained assessment checked the 12-track March 18, 2022 digital album. Track 1 pointed to `5639cdb3-7f91-4a04-bf16-b536ff7c040e`. The Last.fm track claim, `c6200b2b-ae2d-4be7-94e7-d920ac06f853`, did not occur in that tracklist. The assessment flagged a source conflict and a missing exact claimed slot. The current workspace assessments had copied that evidence without performing recording-centered publication checks.

The official European CD independently indexes the same studio recording at track 1. Both the studio and Last.fm-claimed recordings carry ISRC GBAHS2200038 in MusicBrainz. Their reported durations differ by one second. That evidence does not establish audio equivalence. The provider marks `ddf851bb-16ed-465b-9714-3451ce7dbc36` as a Dolby Atmos mix and identifies `570daaca-3900-474e-87f2-314ea151559a` as the March 27 Oakland live performance. The standard album evidence supports the explicitly selected studio MBID. It leaves the edition actually played unknown.

Sources: [MusicBrainz digital edition](https://musicbrainz.org/release/0c41aa7d-de57-4d98-a3c0-4c740834b410), [MusicBrainz CD](https://musicbrainz.org/release/0e4be309-2152-490c-9340-c863b4c9b37a), [Apple Music standard album](https://music.apple.com/us/album/crash/1592545087).

### Heartland

The retained assessment identifies `a79f2c69-4372-4ac3-a357-8b52764a3373` at position 2 on a checked 2012 edition of *Jeopardy*. Three candidates consumed the publication budget before that exact checked track candidate was considered. Thus the investigation never traversed its album release group or checked original tracklists. Two earlier attempts recorded MusicBrainz HTTP 503 responses.

The November 1980 UK release is an 11-track original edition and contains studio “Heartland” at position 2. The 2001 CD has that same recording at position 2 and a separate live recording at position 12. Its complete 15-track sequence must not be presented as the original. The retained MusicBrainz evidence also identifies a distinct Mike Read Session recording (`4a17b7c0-845f-496c-8ed3-96ca5c0890a7`) and another BBC in Concert recording. The observed Last.fm track MBID points to another catalog appearance. No audio equivalence was inferred.

Sources: [1980 UK edition](https://musicbrainz.org/release/c619e486-4dca-4d5e-b6b8-e802a57eec40), [2001 CD](https://musicbrainz.org/release/d0f2193d-45cd-476d-8493-ee10684e55de), [MusicBrainz studio recording](https://musicbrainz.org/recording/a79f2c69-4372-4ac3-a357-8b52764a3373).

## Membership and refresh

Complete observed-album slots receive priority inside the existing three-recording publication budget. A slot starts investigation. It does not establish canonical eligibility. Eligibility still requires exact recording verification, supported album classification, and a complete verified source edition. The assignment and required catalog admission succeed or roll back together. Historical assessments remain available while current logic reassesses the page.

A read-only audit counted 196 production canonical recordings and found one without a verified canonical catalog track slot. Recording 163, “Mind Over Time” (`2c1174e2-988b-484f-bfc9-c247cf9e46c5`), has one historical resolution decision. The candidate applies no data repair, migration or backfill.

## Reproduce

Run `bundle exec rspec spec/requests/verified_recording_membership_spec.rb`. The fixture replays the retained provider candidate order, checked album tracklists, an outdated assessment, and the exact recording and release-group lookups. It checks the confirmation preview, assignment of 19 and 4 observations, source immutability, preserved evidence, and rejection of direct confirmation without membership. The shared browser scenario reuses the same replay in disposable Native Auth.

## Candidate acceptance

- Source SHA `41f963576fbf53146840cd137054c3060be5aa80` and tree `50b030feb57984f1737d926ea511ac188f4c1b70`.
- [Shared Chromium report](shared-chromium.json) binds the native Auth and Resolution checks to the downloaded archive and the [browser environment](browser-environment.json), which records the sealed runtime identity. The four case screenshots below are retained from the report.
- [Disposable seal](disposable-artifact.json) and [Linux staging, service boot, and rollback rehearsal](https://github.com/harvj/muzeum/actions/runs/46098532853).
- No migrations. The rehearsal compared the two sealed releases and exercised compatible rollback. The artifact digest stayed unchanged through boot, authenticated smoke traffic, and a same-process footer transition.
- [Exact-SHA CI](https://github.com/harvj/muzeum/actions/runs/46098512355).

| Case | Desktop | Mobile |
| --- | --- | --- |
| Crash, all 19 observations and 12-track album | [Desktop](desktop-release-backed-crash.png) | [Mobile](mobile-release-backed-crash.png) |
| Heartland, all four observations and 11-track album | [Desktop](desktop-release-backed-heartland.png) | [Mobile](mobile-release-backed-heartland.png) |
