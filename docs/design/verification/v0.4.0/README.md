# Muzeum v0.4.0 verification

The [desktop](light-beams-desktop.webp) and [mobile](light-beams-mobile.webp) Chrome captures show the same group of three LIGHT BEAMS observations. Listening writes ran against a disposable database. The tracklist fixture carries real MusicBrainz identities. [MusicBrainz release](https://musicbrainz.org/release/1f2f9922-162d-42d0-a94d-b965bb59dcff)

## Performance

Rails requests used Ruby 3.4.13 and a disposable PostgreSQL database with 293,000 observations, including 147 exact matches for Boards of Canada's Roygbiv. Both builds used identical data and a process-local cache. The baseline was deployed v0.3.6 at `c37a00dcf058e87fdc59644e9e444c001e29622f`. Cold is the first request, and warm server values are the median of three subsequent requests. SQL query counts exclude transactions and schema introspection. Chrome navigation used local loopback and measures browser load independently of the Rails request.

| Page | Cold server (ms) | Warm server (ms) | Warm SQL (ms) | Warm SQL queries | Warm Rails views (ms) | Warm Chrome load (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Archive summary | 1150.8 → 330.2 | 1105.8 → 4.8 | 1101.0 → 1.0 | 10 → 5 | 0.9 → 0.9 | 1083.7 → 16.5 |
| Music Has the Right to Children | 696.2 → 24.6 | 684.5 → 8.1 | 678.7 → 3.2 | 14 → 14 | 1.4 → 1.3 | 997.1 → 24.4 |
| Roygbiv | 862.9 → 15.4 | 848.0 → 9.2 | 840.0 → 4.1 | 16 → 15 | 3.1 → 1.7 | 1215.8 → 26.5 |

Production baseline logs showed the Archive summary at 4108 ms total, with 4096.1 ms in SQL and 2.4 ms in views. The Boards of Canada release took 4147–4599 ms in the sampled production requests, with 4134–4565.1 ms in SQL and 3.2–7.9 ms rendering. The Roygbiv comparison and all after measurements are disposable. A warm summary using the production shared cache and actual network latency still need measurement after authorized deployment. The disposable cold summary exceeded the 300 ms server target.

The summary replaces six observation scans with a single grouping query and briefly caches exact results by the current source-account observation watermark. An import advances the watermark and recomputes the summary. Live access checks precede cache lookup. Recording and release details select observations from decisions for the requested recordings and apply the normal effective ledger precedence. A concurrent partial index supports this lookup. Initial catalog pages cap tracklists at 100 and release appearances at 30, with links to later entries. There are no synchronous provider requests in these render paths.
