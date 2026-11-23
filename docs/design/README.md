# Muzeum P1.4 design screenshots

These images document the table and navigation restoration in [Issue #22](https://github.com/harvj/muzeum/issues/22), implemented at [`7c6e903`](https://github.com/harvj/muzeum/commit/7c6e90357a7785445954a6f98c7b0570eb05df85).

## Operator references

The PNGs in [references/](references/) preserve the supplied image bytes. Filenames describe the subject and, for Muzeus, the original capture date.

- **Navigation** — [Auth Profile menu](references/auth-profile-menu.png) and [Muzeum menu before restoration](references/muzeum-profile-menu-before.png)
- **Muzeus plays** — [2022 plays](references/muzeus-2022-03-17-plays.png), [2023 date groups](references/muzeus-2023-03-26-plays-by-day.png), [2024 plays table](references/muzeus-2024-04-09-plays-table.png), [2024 day heading](references/muzeus-2024-05-23-plays-day-heading.png)
- **Muzeus releases** — [rankings](references/muzeus-2022-06-01-release-rankings.png), [release list](references/muzeus-2022-09-15-release-list.png), [release heading](references/muzeus-2024-08-19-release-heading.png)
- **Muzeus artists** — [artist list](references/muzeus-2023-09-25-artist-list.png) and [artist rankings](references/muzeus-2023-12-02-artist-rankings.png)

## Verification captures

The selected browser captures in [verification/](verification/) use synthetic Rails fixtures. Desktop captures are 1440 × 960, and mobile captures are 390 × 844.

| View | Captures |
| --- | --- |
| Archive | [Before, desktop light](verification/archive-before-desktop-light.png) · [After, desktop light](verification/archive-after-desktop-light.png) · [After, desktop dark](verification/archive-after-desktop-dark.png) · [After, mobile light](verification/archive-after-mobile-light.png) |
| Release detail | [Before, desktop light](verification/release-before-desktop-light.png) · [After, desktop light](verification/release-after-desktop-light.png) · [Hover inversion](verification/release-link-hover.png) · [Keyboard focus inversion](verification/release-link-keyboard-focus.png) |
| Resolution and navigation | [Resolution, desktop dark](verification/resolution-after-desktop-dark.png) · [Profile and Appearance, desktop](verification/profile-appearance-desktop.png) |

The historical captures show genre buckets and ranking displays. The verification captures record the implemented presentation scope. Genre-bucket classification remains open, and ranking calculations and badges are tracked in [Issue #21](https://github.com/harvj/muzeum/issues/21).

## Table fidelity revision

The comparison sheets place the Muzeus reference, the first P1.4 implementation, and the revised Muzeum view at equal panel widths. Both Muzeum desktop captures use the same 1440 × 960 viewport and fixture. The historical release image contains the heading only, so the track-list comparison uses the two Muzeum captures.

| View | Evidence |
| --- | --- |
| Archive | [Side-by-side](verification/table-fidelity/archive-comparison.png) · [Desktop light](verification/table-fidelity/archive-desktop-light.png) · [Desktop dark](verification/table-fidelity/archive-desktop-dark.png) |
| Full names | [Desktop hover](verification/table-fidelity/archive-desktop-hover.png) · [Desktop keyboard focus](verification/table-fidelity/archive-desktop-focus.png) · [Mobile compact](verification/table-fidelity/archive-mobile-dark.png) · [Mobile expanded](verification/table-fidelity/archive-mobile-full-names.png) |
| Release | [Side-by-side](verification/table-fidelity/release-comparison.png) · [Desktop dark](verification/table-fidelity/release-desktop-dark.png) |

The fixture has 64 observations across two days, 50 displayed observations, and a synthetic two-disc, 28-slot listing modeled on *Mellon Collie and the Infinite Sadness*. At 1440 × 960 the number of complete rows above the fold grew from 23 to 33 on Archive and from 19 to all 28 on the release. Day summaries count the plays displayed in each group.

Recording links follow the listener’s existing resolution. An Archive release link requires a unique verified release with the reported title and the resolved recording as a member. A reported edition ID must agree when present. The link shows membership and does not provide per-play release credit. Unresolved observations keep their source names and observation links. The gutter and trailing column leave room for a future marker and play-count treatment. Genre categories, ranks and play bars remain open or deferred as described above.

Warmed local Rails request medians on matched disposable PostgreSQL fixtures with 20,000 observations and a fully resolved recent page were 62.0 → 67.1 ms for Archive, 54.5 → 54.3 ms for release detail, and 14.1 → 13.8 ms for the Resolution observation. Each median uses 15 requests after three warmups. Archive query count grew from 12 to 15, with the added catalog reads batched across the displayed plays.

## Universal footer

Chromium captures from the local browser fixture show the sign-in page at initial load and the Archive scrolled to its final content. The screenshot version is fixture metadata bound to the fixture SHA. The Site Art controller decodes the bundled byte-identical texture files as deterministic image fixtures.

| Page | Desktop, 1440 × 960 | Mobile, 390 × 844 |
| --- | --- | --- |
| Short sign-in | [Light](verification/footer/footer-short-desktop-light.webp) | [Dark](verification/footer/footer-short-mobile-dark.webp) |
| Long Archive | [Light](verification/footer/footer-long-desktop-light.webp) | [Dark](verification/footer/footer-long-mobile-dark.webp) |

The browser regression covers both themes at both viewport sizes. It checks that the short page has no vertical overflow, the long page scrolls, the footer clears the content, and the centered copyright and version have no top separator.

## Site Art v1

The [approval preview](site-art-v1.md) shows the corrected reader with current Site Art artwork on desktop and mobile, including the light-theme contrast fallback and the limestone treatment under review.

## Release design reviews

Keep the final Chrome review screenshots for visual UI changes under `docs/design/` with relative links in the review README. Temporary captures can stay outside the repository during development.

- [v0.6.7 entity headings and Recording Resolution](v0.6.7/)

- [Catalog, Resolution, and Archive polish](catalog-resolution-archive/)

- [Global header navigation states](header-navigation/)
