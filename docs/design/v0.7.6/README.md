# v0.7.6 listening history controls

- [Desktop light](artist-3y-months-desktop.webp)
- [Mobile dark](artist-3y-months-mobile.webp)

The disposable Charli xcx archive contains activity across 2013–2026. The representative screenshots use a three-year monthly window. The complete verification matrix includes all period and grouping combinations, leap-year navigation, sparse activity and empty windows. [Calendar checks](calendar-checks.json)

Period, grouping and window links update the catalog frame and advance browser history without using a fragment. The active period and grouping are plain labels with current-state semantics. Every January slot carries the year, followed by Apr, Jul and Oct on their actual slots. The selected date range remains visible for partial historical windows.

The Chrome regression exercises Recording, Release and Artist pages in desktop/mobile light and dark configurations. It starts with the chart well below the document top, verifies scroll position after mouse and keyboard navigation, checks that the active label is noninteractive and does not change on hover, and checks Back and reload. No observations or aggregation formulas change.

    BROWSER_TESTS=1 bundle exec rspec spec/system/listening_history_acceptance_spec.rb

[Release membership and provenance acceptance](../release-membership/README.md)

## Resolution

[Structured title interpretation review](title-interpretation/README.md)
