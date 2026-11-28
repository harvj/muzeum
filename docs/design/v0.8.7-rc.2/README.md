# Muzeum v0.8.7-rc.2

Source `0f3db9df2496bc0a5d53f23039f873e9578be86a`.

## Heartland investigation

Production assessment 322 verified the studio recording `a79f2c69-4372-4ac3-a357-8b52764a3373` and browsed its release appearances. The *Jeopardy* release-group lookup returned HTTP 503, leaving that group pending. Worker jobs 231 and 232 completed with zero provider requests. Assessments 323 and 324 retained the pending group. The rc.1 disposable fixture started at an older assessment version, which took a different path and performed discovery.

The manual refresh regression replays the current-version pending publication history. Refresh retries the incomplete history through the existing bounded provider session. It retains the other histories and checked tracklists. The verified 1980 configuration has eleven tracks and the studio recording at track two. The expanded reissue and competing recordings remain distinguishable. Crash retains a twelve-track configuration supported by sixteen source editions.

- [Exact-SHA CI](https://github.com/harvj/muzeum/actions/runs/46120226850)
- [Disposable Linux deployment and rollback](https://github.com/harvj/muzeum/actions/runs/46120247714)
- [1980 Jeopardy edition](https://musicbrainz.org/release/c619e486-4dca-4d5e-b6b8-e802a57eec40)

The browser scenarios use disposable accounts and data. Live checks compare production observation, decision, and catalog fingerprints and leave the release candidate available for owner review.

## Authenticated Chromium

All eleven shared Chromium steps passed against the sealed candidate with disposable native Auth. Two earlier runs reached a successful logout response and removed the session cookie but timed out while checking the post-logout landing page. The passing rerun verified that both private Archive routes redirected to the public landing page. The harness then verified session removal in Muzeum and grant revocation in Auth.

- [Shared report](shared-chromium.json)
- [Heartland desktop](desktop-release-backed-heartland.png) and [mobile](mobile-release-backed-heartland.png)
- [Crash desktop](desktop-release-backed-crash.png) and [mobile](mobile-release-backed-crash.png)
