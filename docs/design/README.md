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
