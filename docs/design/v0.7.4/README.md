# Muzeum v0.7.4 entity page visual acceptance

Chrome rendered a disposable Charli xcx catalog with 585 resolved plays and the test clock set to November 25, 2026. Desktop captures use a 1440 × 900 light viewport. Mobile captures use a 390 × 844 dark viewport. This matrix covers every allowed period and grouping combination.

| Period and grouping | Entity | Window | Slots / empty | Desktop | Mobile |
| --- | --- | --- | --- | --- | --- |
| All + Years | Charli xcx | Full history | 14 / 3 | [Desktop](artist-all-years-desktop.webp) | [Mobile](artist-all-years-mobile.webp) |
| All + Months | Charli | Full history | 162 / 65 | [Desktop](release-all-months-desktop.webp) · [Oldest end](release-all-months-desktop-scrolled.webp) | [Mobile](release-all-months-mobile.webp) |
| 3y + Years | Next Level Charli | 2024–2026 | 3 / 0 | [Desktop](recording-3y-years-desktop.webp) | [Mobile](recording-3y-years-mobile.webp) |
| 3y + Months | Charli xcx | 2024–2026 | 36 / 7 | [Desktop](artist-3y-months-desktop.webp) | [Mobile](artist-3y-months-mobile.webp) |
| Year + Months | Charli | 2026 | 12 / 2 | [Desktop](release-year-months-current-desktop.webp) | [Mobile](release-year-months-current-mobile.webp) |
| Year + Months | Charli | 2025, previous | 12 / 3 | [Desktop](release-year-months-previous-desktop.webp) | [Mobile](release-year-months-previous-mobile.webp) |
| Year + Days | Next Level Charli | 2024, leap year | 366 / 353 | [Desktop](recording-year-days-leap-desktop.webp) | [Mobile](recording-year-days-leap-mobile.webp) |
| 6m + Months | Charli xcx | Jun–Nov 2026 | 6 / 0 | [Desktop](artist-6m-months-desktop.webp) | [Mobile](artist-6m-months-mobile.webp) |
| 6m + Days | Charli | Jun–Nov 2026 | 183 / 112 | [Desktop](release-6m-days-desktop.webp) | [Mobile](release-6m-days-mobile.webp) |
| 90d + Days | Next Level Charli | Aug 28–Nov 25, 2026 | 90 / 21 | [Desktop](recording-90d-days-current-desktop.webp) | [Mobile](recording-90d-days-current-mobile.webp) |
| 90d + Days | Next Level Charli | May 30–Aug 27, 2026, previous | 90 / 88 | [Desktop](recording-90d-days-previous-desktop.webp) | [Mobile](recording-90d-days-previous-mobile.webp) |
| 30d + Days | Next Level Charli | Oct 27–Nov 25, 2026 | 30 / 7 | [Desktop](recording-30d-days-current-desktop.webp) | [Mobile](recording-30d-days-current-mobile.webp) |
| 30d + Days | Next Level Charli | Sep 27–Oct 26, 2026, previous | 30 / 5 | [Desktop](recording-30d-days-previous-desktop.webp) | [Mobile](recording-30d-days-previous-mobile.webp) |


The browser compared each displayed calendar slot and bar to independently grouped fixture observations. It checked chronological direction, 2 px gaps between 20 px annual, 10 px monthly, and 8 px daily bars, proportional lengths within 1 CSS pixel, sparse non-overlapping labels, and January year markers for day and month groupings. Monthly labels use abbreviated month names. Every nonempty window’s peak bar filled the plot on both axes, and the axis showed that window’s maximum. Navigation tests verified the scale resets between windows and groupings, and the empty window retained its slots with a zero axis and no fills. The long monthly plot scrolls horizontally on desktop and vertically on mobile. The current 30-day screenshot shows the disabled forward arrow, and the previous-window screenshots show both arrows enabled. Totals below the plot remain all time.

The current three-year window includes this calendar year and its two predecessors. The current six-month window includes this month and its five predecessors. Calendar windows reserve empty intervals through the end of their last calendar year or month. Day windows end on the current UTC date and move by their exact length.

[Measured browser results](calendar-checks.json) · [Chrome acceptance spec](../../../spec/system/listening_history_acceptance_spec.rb) · [Date-window tests](../../../spec/services/catalog_listening/window_spec.rb)

To regenerate screenshots from the repository root with Chrome and the Rails test database ready:

```sh
mkdir -p /tmp/muzeum-listening-review
BROWSER_TESTS=1 LISTENING_REVIEW_DIR=/tmp/muzeum-listening-review \
  bundle exec rspec spec/services/catalog_listening/window_spec.rb spec/system/listening_history_acceptance_spec.rb
```
