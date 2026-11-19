# Site Art v1 approval preview

The captures use the corrected Muzeum reader and a synthetic public archive in Chromium. Desktop is 1440 × 960 and mobile is 390 × 844. Illumination is paused for a reproducible crop.

## What the reader will display

| Theme | Desktop | Mobile |
| --- | --- | --- |
| Light · bundled limestone fallback | [Desktop](verification/site-art-v1/fallback-desktop-light.webp) | [Mobile](verification/site-art-v1/fallback-mobile-light.webp) |
| Dark · current Site Art onyx | [Desktop](verification/site-art-v1/published-desktop-dark.webp) | [Mobile](verification/site-art-v1/published-mobile-dark.webp) |

## Current Site Art limestone for review

These diagnostic captures bypass the contrast fallback so the two limestone treatments can be reviewed on the same image. The Site Art source adds a light header with a 95% dark glyph shadow. The published version uses dark header text. Both specify a light footer.

| Treatment | Desktop | Mobile |
| --- | --- | --- |
| Published manifest | [Desktop](verification/site-art-v1/published-desktop-light.webp) | [Mobile](verification/site-art-v1/published-mobile-light.webp) |
| Site Art repository source | [Desktop](verification/site-art-v1/source-desktop-light.webp) | [Mobile](verification/site-art-v1/source-mobile-light.webp) |

The image bytes match the live manifest release `02cb2f04b3cec1eae1ffda71a3cabca40883cf8ee1b155601745e17e1a746f39`. The alternate limestone treatment comes from Site Art commit `5b874bd`.

On the archive page, the limestone crop puts exposed text over a wide luminance range. A conservative sample of the raw image under the header, first navigation link, introduction and footer found pixels near 1:1 contrast in both limestone treatments, before accounting for the shadow. The shadow improved visual separation in parts of the crop, but the captures still show uneven legibility. The same sampling on onyx found minimum ratios of 10.36:1 on desktop and 6.77:1 on mobile. These samples cover the captured page and resting illumination only.

Muzeum uses bundled limestone for the reviewed ivory-cliff image digest. **Open** — which light artwork or revised treatment should replace the bundled fallback? Recheck the exposed roles on both desktop and mobile before admitting the ivory-cliff image. Artwork backing is optional under v1. Muzeum leaves the existing header, content and footer surfaces in place and applies declared shadows directly to glyphs.

## Tall home page

The 1408 × 1118 home page captures approximate the reported Brave viewport. Artwork sizing is in Muzeum’s fingerprinted stylesheet so a cached copy of the public stone stylesheet cannot leave the remote image at its intrinsic height.

- [Current limestone, diagnostic](verification/site-art-v1/published-tall-home-light.webp)
- [Bundled light fallback](verification/site-art-v1/fallback-tall-home-light.webp)
- [Current onyx](verification/site-art-v1/published-tall-home-dark.webp)

Approval is pending. The capture and reader changes remain local.

[Site Art Consumer Presentation Specification v1](https://github.com/harvj/site-art/blob/5b874bd/ops/presentation-spec-v1.md)
