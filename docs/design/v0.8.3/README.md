# v0.8.3 Resolution Evidence correction

The deployed v0.8.2 baseline was replayed with assessment snapshots 286, 290 and 291 and the eight Birthday observation IDs and timestamps. The fixture was made from a read-only production snapshot. The browser runs use disposable observations and accounts with no production session material.

The [v0.8.2 replay](v082-evidence-before.png) reproduces `/resolution/293137?section=evidence`. The Evidence tab expanded the legacy candidate partial, which independently computed original-release proposals. It offered the disputed August 26 US edition even though the reviewed Candidates path handled it as disputed. The earlier v0.8.2 screenshots exercised the Candidates route for Birthday. The production assessment already had the current policy and three adjacent source programs.

Both tabs now open with the same recording choice for reviewed release groups. The circular checkbox previews a recording without committing an assignment. The action and observation count precede the optional release disclosure. Recording-only confirmation retains the individual-override behavior. UK, September US and Japanese configurations and grouped adjacent programs are available inside that disclosure, and their tracklists begin collapsed. The disputed August source is labeled as evidence. The two other Blur recordings in the canonical-library browser regression retain recording-specific provenance, including the Wear Me Down mispressing. Unreviewed release groups retain their existing construction workflow.

## Browser review

| State | Desktop | Mobile |
| --- | --- | --- |
| Recording unselected, release evidence collapsed | [Desktop](desktop-recording-unselected.png) | [Mobile](mobile-recording-unselected.png) |
| Recording selected | [Desktop](desktop-recording-selected.png) | [Mobile](mobile-recording-selected.png) |
| Confirmation preview and action | [Desktop](desktop-confirmation-preview.png) | [Mobile](mobile-confirmation-preview.png) |
| Release evidence expanded | [Desktop](desktop-release-evidence-expanded.png) | [Mobile](mobile-release-evidence-expanded.png) |

[Shared browser report](evidence.json) · [Artifact identity](sealed-identity.json) · [Source and environment binding](binding.json)

Exact candidate `eff96e297537e112699c9584cf4410e341780708` on `release/v0.8.3`. [Hosted CI](https://github.com/harvj/muzeum/actions/runs/46068180742) · [Disposable Capistrano staging](https://github.com/harvj/muzeum/actions/runs/46068189980). No migrations.

All 418 Rails and Chromium examples passed. Shared Chromium passed all nine steps, including native Auth and confirming eight disposable observations with no release selection. The sealed disposable inventory SHA-256 is `f07a3d545287d997ff1a38f0dd718a2c18919d09d14496190199570d7162ad4d`.

[Signed Application Shell v2.0.0 preflight](shell/signed-preflight.txt) · [Executable SH-08 evidence](shell/sh08-executable.json)
