# Site Art presentation verification

These captures document the earlier scrim-based reader. See the [Site Art v1 approval preview](../../design/site-art-v1.md) for the corrected implementation and current artwork.

The captures use the published limestone and onyx PNGs from manifest release
`ead56c4ed4eb45d518d7469c874ce381bad42b5c1868c02a15a887c98745d84e`.
The before views supply the new image URLs with local foreground styles.
The after views combine the live manifest with the proposed limestone bottom
treatment in Site Art's local source manifest. The live manifest was still flat
at capture time. The earlier production reader rejects structured metadata and
uses its last accepted snapshot or bundled artwork.

| View | Before | After |
| --- | --- | --- |
| Desktop light, 1440 × 960 | [Capture](screenshots/desktop-light-before.webp) | [Capture](screenshots/desktop-light-after.webp) |
| Desktop dark, 1440 × 960 | [Capture](screenshots/desktop-dark-before.webp) | [Capture](screenshots/desktop-dark-after.webp) |
| Mobile light, 390 × 844 | [Capture](screenshots/mobile-light-before.webp) | [Capture](screenshots/mobile-light-after.webp) |
| Mobile dark, 390 × 844 | [Capture](screenshots/mobile-dark-before.webp) | [Capture](screenshots/mobile-dark-after.webp) |

Muzeum applies a neutral scrim under the publisher backing on exposed text.
The worst-case foreground contrast over the composite, using black and white
image pixels as bounds and excluding the shadow, is 5.24:1 for the limestone
header, 4.80:1 for its light footer, and 5.05:1 for the onyx header and footer. The page retains local form and card palettes,
visible keyboard focus, and native forced-colors behavior.

Rails refreshes a validated snapshot asynchronously on requests. Open visible
pages check the same-origin snapshot about once per minute. A cold worker can
first return an empty snapshot while it refreshes. Open pages retain their
last valid snapshot through that response or an outage. A valid publication
with an omitted slot restores the local artwork for that slot. Unknown optional
treatments are dropped before the snapshot reaches the browser. A failed image
decode clears that image's overlay treatment. A newer manifest with an
unchanged image URL can update the visible treatment without reloading the
image.

Production uses the existing CSP and guarded code-only deployment workflow.
After deployment, verify both decoded PNGs and their treatments, favicon
fallback, and manifest refresh from the live site. The limestone footer
becomes light when Site Art separately publishes the bottom override.
