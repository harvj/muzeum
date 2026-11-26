# Resolution release provenance

Preview against production Muzeum v0.7.4 (`f4e5aa959b2d5464a9a2c82508c8f514acddbe0b`). Chrome screenshots use disposable accounts and retained public MusicBrainz edition projections. Production observations and catalog decisions were inspected read-only.

| Observation | Desktop | Mobile | Acceptance |
|---|---|---|---|
| 293094 · Tove Lo, Thousand Miles | [Desktop](queen-desktop.webp) | [Mobile](queen-mobile.webp) | One established canonical tracklist, all 16 Canadian tracks, September 24, 2014. Thousand Miles is highlighted. Alternative editions start closed. |
| 293186 · Interpol, Pace Is the Trick | [Desktop](interpol-desktop.webp) | [Mobile](interpol-mobile.webp) | The instrumental traces to medium 2, track 7 of the [2007 US CD + CD-R edition](https://musicbrainz.org/release/90a206e9-968b-426b-ada8-e4ef190e4eac). The 12-track audio program is a sibling proposal for separate catalog review. The anniversary DVDs remain source evidence. |
| 293151 · Songs: Ohia, Tenskwatawa | [Desktop](songs-ohia-desktop.webp) | [Mobile](songs-ohia-mobile.webp) | The [1997 CD](https://musicbrainz.org/release/78569136-057d-48b6-83a6-96a7eea54977) has 13 tracks and no Greenbrier. The [2004 vinyl](https://musicbrainz.org/release/37969e2b-b9bf-4fda-bf8b-5c58000ffdbb) has 14 tracks and contains Greenbrier. An evidence-only investigation can check its separate history without changing the Tenskwatawa candidate. |

The alternative-source section displays edition and recording links. Selecting one loads that source's detailed tracklist or appearances. Investigating a recording uses the existing background queue and appends publication evidence to the assessment. The recording shortlist, canonical catalog, and listening observations are preserved.

The existing release model can represent separate programs without a migration. Each canonical release has its own source edition, ordered track slots, and statistics. Resolution surfaces a substantially distinct bonus program for separate catalog review. Confirmation of the current recording does not admit a sibling. A separate sibling-admission action is outside this preview. The track's earliest checked MusicBrainz appearance may leave original publication unresolved. The edition played remains unverified.

## Detail request measurements

Authenticated Rails integration requests against disposable PostgreSQL, with full retained edition evidence for each of the three cases. Each row uses the first request and the median of requests 3–7 in the same process. Bytes are uncompressed HTML. SQL is the number of uncached application statements. These measurements exclude network transfer, browser paint, and production-scale queue/index performance.

| Case | First request, baseline → preview | Warm median, baseline → preview | HTML bytes, baseline → preview | SQL statements |
|---|---:|---:|---:|---:|
| Queen of the Clouds | 108 → 99 ms | 55 → 68 ms | 25,717 → 24,559 | 42 |
| Our Love to Admire | 77 → 114 ms | 79 → 126 ms | 24,376 → 35,601 | 27 |
| Songs: Ohia | 17 → 17 ms | 20 → 22 ms | 20,338 → 21,282 | 27 |

The first version rendered every appearance's source details in the initial HTML. Loading detailed provenance on demand reduced the Interpol response from 59,554 to 35,601 bytes. The remaining overhead includes the edition and recording links and verification against the checked base. Broader #25 performance acceptance remains open.

## Reproduce the focused checks

```sh
bundle exec rspec spec/requests/canonical_workspace_spec.rb -e 'investigates Greenbrier'
BROWSER_TESTS=1 bundle exec rspec spec/system/canonical_library_spec.rb -e 'three production-derived'
```

Set `P151_PREVIEW_DIR` to an existing writable directory to regenerate the six WebP screenshots.
