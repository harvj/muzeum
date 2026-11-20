# P1.5.2b Discovery coverage and edition semantics

## Production case 292999

A bounded read-only inspection found five matching Last.fm observations for The Get Up Kids, Regent's Court, and There Are Rules (Deluxe Edition). The latest retained assessment ran two MusicBrainz calls. Its three search results all used “Regent’s Court” with a typographic apostrophe. P1.5.1 required a comparable title, a verified source identifier, or a checked edition slot for eligibility. The title comparison failed, the Last.fm track MBID returned HTTP 404, and the source supplied no release MBID. The assessment retained three search results and ranked none.

MusicBrainz lists recording `0772fc8e-567b-47ed-bbcc-15d9c2fa46b6` at disc 1, track 2 on its 18-track digital deluxe release. The label and band independently corroborate the title and position on the deluxe program. The original album and the Daytrotter Session have distinct MusicBrainz recording IDs. No fetched recording relationship or ISRC established that the original and deluxe IDs represent the same recording. The played edition stays unverified. [MusicBrainz deluxe release](https://musicbrainz.org/release/96fdedfd-ba26-4ff4-a7bc-faf54879f158), [original US album](https://musicbrainz.org/release/a6d2beb7-6acf-4bfb-a2bf-e2a6249f6504), [Polyvinyl deluxe tracklist](https://www.polyvinylrecords.com/products/the-get-up-kids-there-are-rules-deluxe-edition), [band release](https://thegetupkids.bandcamp.com/album/there-are-rules-deluxe-edition).

## Discovery policy

Normalize typographic apostrophes for candidate comparison. Stored observations and surface keys stay intact. Look for catalog matches and verified stored tracklists first. For insufficient evidence, the existing asynchronous MusicBrainz investigation can check related candidate releases and perform one artist-scoped release title search. A checked medium needs a matching declared track count, a matching slot title, and a compatible artist credit. Keep catalog appearances keyed to exact recording MBIDs and preserve distinct version IDs. A checked appearance contributes one point for a related release title or two for a matching title or catalog caption. Appearance alone cannot produce a recommendation or an edition assignment. A recording ID that conflicts with a different checked candidate matching the album caption now withholds the recommendation.

The existing provider ledger and job budgets still apply. Discovery itself considers up to five release search results, two checked release details including any prior edition lookup, and 100 slots per release. An explicit source release MBID uses its existing single lookup. The local path limits recording rows to 25 and editions to four. The decision snapshot retains candidate inputs, scores, and the checked appearance with release and track identifiers. Batch review and optional operator comments retain their existing behavior. There are no migrations.

## Replay results

Run `RAILS_ENV=test bin/rails runner script/resolution_discovery_replay.rb` against the archived MusicBrainz projections in the discovery fixture. It includes the production candidate set and source claims for Regent's Court, three previous held-out discovery misses, and three edition controls. The controls cover original material, a newly introduced bonus track, and previously released EP material on the deluxe program. Artist and label tracklists corroborate their release context. The Queen cases replay the same missing candidates and misleading identifier used in prior evaluation. They are constructed source claims with independently corroborated recording context. [Original EP](https://thegetupkids.bandcamp.com/album/simple-science), [Queen Montreal release](https://musicbrainz.org/release/1586ee16-f598-4bf4-90d6-133128c2df94), [Queen Wembley release](https://musicbrainz.org/release/4fdc2eac-8574-4114-b36f-c7fcfe619178).

| Measure | P1.5.1 replay | Discovery replay |
| --- | ---: | ---: |
| Reviewed recording in shortlist | 0/7 | 7/7 |
| Previous held-out discovery misses recovered | 0/3 | 3/3 |
| Correct unique top rank | 0/7 | 4/7 |
| Correct recommendations | 0 | 0 |
| False positive recommendations | 1 | 0 |
| Recommendations withheld | 6/7 | 7/7 |
| Included non-reference identities | 5 | 7 |
| Captured provider calls per case | 1–2 | 2–5 |

The two additional non-reference inclusions are separate Regent's Court appearances from the original album and the Daytrotter Session. Both are valid catalog alternatives. Counting every non-reference identity as an inclusion error provides a conservative bound for the labeled examples. Regent's Court ranks deluxe 9, original 8, and session 7. The three prior discovery misses still lack a correct unique top rank. All seven examples were selected to probe known failure modes. These fractions do not estimate archive-wide coverage or recommendation quality.

The offline application replay took 0.30–1.12 ms per improved case in one local run, excluding database and network latency. A local title regression with 20,000 unrelated recording rows took 14 ms in one disposable run. The legacy local title lookup can still scan the catalog. A verified explicit edition or exact MBID remains more reliable than release-title search, which can miss translated or substantially renamed editions and results outside the bounded search. The frozen release and production assessment were left intact.

An existing completed assessment such as observation 292999 needs a fresh investigation to capture the new evidence after a separately authorized deployment.
