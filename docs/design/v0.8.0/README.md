# Muzeum v0.8.0 acceptance

The milestone includes the accepted configuration work at
`45cdaa431da8a0e5a757ce97a1006b6704851908`.
[Leisure comparison, source evidence and screenshots](../release-configurations/README.md).

| Scenario | Evidence |
|---|---|
| UK, September US, Japan and anniversary configuration selection, scoped release dates and totals | [Configuration request coverage](../../../spec/requests/release_configurations_spec.rb) |
| Adjacent program discovered by exact recording and admitted only on explicit review | [Recording-first replay](../../../spec/services/recording_resolution/recording_provenance_spec.rb) and [admission request coverage](../../../spec/requests/release_configurations_spec.rb) |
| Queen of the Clouds review, observed totals unchanged after confirm and reject | [Desktop confirmation](queen-inference-desktop.png), [mobile rejection](queen-inference-mobile.png), [request coverage](../../../spec/requests/short_track_inference_spec.rb) |
| Shared authenticated browser runner | [Reproduction](../../../spec/browser_acceptance/README.md) and [prior pilot evidence](../shared-browser-acceptance/README.md) |

The Queen fixture uses positions 5–7 of the retained Canadian 16-track
MusicBrainz edition `9cd3b250-dc88-450f-8836-dbd0e0fa2ccc`. The observation
timestamps are disposable. “Timebomb” is 214 seconds, “The Love (interlude)”
is 5 seconds, and “Moments” starts 219 seconds after the first observation.
Only the two observed songs contribute to the release's counts and charts.
Review attempts are private and append-only. Existing recording-surface
resolution and per-observation overrides continue to apply to observed plays.

The Leisure replay identifies the three-track original “She’s So High” single
from its exact “I Know (extended)” appearance. It preserves partial browse
results and uncertainty about broader recording relationships. The August US
edition remains disputed, and “Won’t Do It” has no completed provider browse in
the retained research. No Leisure same-group sibling has sufficient evidence
for admission. Existing same-group conflict checks stay in force. No discography
crawl or cross-release import cascade is performed.

```sh
bundle exec rspec spec/requests/release_configurations_spec.rb spec/requests/short_track_inference_spec.rb spec/services/recording_resolution/recording_provenance_spec.rb
BROWSER_TESTS=1 bundle exec rspec spec/system/canonical_library_spec.rb -e 'switches verified Leisure configurations' -e 'reviews a Queen of the Clouds interlude'
```
