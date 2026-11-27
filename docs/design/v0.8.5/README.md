# v0.8.5 Leisure visibility correction

## Read-only production findings

Birthday surface decision 40, from assessment 299, assigned eight observations to recording 205. The browser payload was not retained. The persisted records from the same transaction establish the accepted choices.

| Persisted result | Evidence |
| --- | --- |
| One canonical Leisure release linked to Blur | Release 16, UK source `d550f756-9e71-3e6b-8492-84a37154c10f`, import 202, 12 verified base slots |
| UK configuration and listener preference | Snapshot 3, August 27, 1991, preference decision 3 |
| US alternate source configuration | Snapshot 4, September 24, 1991, source `d81bfb74-5d2e-4dcf-956f-550cfde5eed5` |
| Three independent singles | Releases 17–19, imports 203–205 |

The artist page previously showed only release-ranking results. Leisure's verified UK source has `original_context: false` under the existing rule because the retained provider release-group first date precedes it by one day. No member was credited with its first verified publication on that exact UK edition, and no explicit ranking preference overrides the default. The three singles have the original-context flag. The album exists and the link to Blur exists. The [v0.8.4 disposable replay](v084-artist-before.png) shows the omission.

The new **Other canonical releases** section exposes verified canonical releases excluded by the ranking filter, with the listener's effective release date. The ranking and listening rules are unchanged. The pending preview names album admission and the role of the preferred base separately. No catalog repair is needed for visibility. Any future correction to disputed publication evidence is a separate catalog operation.

## Verification

The disposable Birthday replay admitted one album with two verified configurations and the three singles. It switched from the UK preference to the US preference and verified the date and effective listening totals. A separate UK-only fixture play contributes to the UK total and drops out of the US total. The eight Birthday observations and their recording assignment stay the same.

- [Desktop artist page](desktop-artist-canonical-leisure.png)
- [Mobile artist page](mobile-artist-canonical-leisure.png)
- [Shared native Auth report](evidence.json) and [exact binding](binding.json)

Candidate `931c234323e57a06be8102f730846af4b86c9f20` on `release/v0.8.5`. [Exact-SHA CI](https://github.com/harvj/muzeum/actions/runs/46083667274) · [Disposable staging](https://github.com/harvj/muzeum/actions/runs/46083683790). No migrations.

The full application suite passed 418 examples. The final shared native Auth run passed all ten steps, including the artist-page replay and logout. [Signed Shell v2.0.0 preflight](shell/signed-preflight.txt) · [Executable SH-08 evidence](shell/sh08-executable.json).
