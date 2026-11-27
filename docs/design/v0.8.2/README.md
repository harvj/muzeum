# Muzeum v0.8.2 release qualification

- Published baseline: [v0.8.1](https://github.com/harvj/muzeum/releases/tag/v0.8.1), `6b558456bd3778407e102973a30aa326a36865f1`.
- Candidate: [`bfeabafeae5267425bc3906a9639ba8bc2799779`](https://github.com/harvj/muzeum/commit/bfeabafeae5267425bc3906a9639ba8bc2799779), branch `release/v0.8.2`.
- [Exact-SHA CI](https://github.com/harvj/muzeum/actions/runs/46051082594) · [Disposable Linux staging and rollback rehearsal](https://github.com/harvj/muzeum/actions/runs/46051147435).

The release combines the reviewed Unified Resolution branch with the local circular checkbox stylesheet and browser regression. It also includes the disposable-auth browser scenario that was previously carried separately with the review evidence. The original review and its screenshots remain available in the [Unified Resolution evidence](https://github.com/harvj/muzeum/blob/5bd93dd8184969780f7b376c87a8f83e0fb40f4b/docs/design/unified-resolution/README.md).

No migrations, schema files, or protected deployment configuration changed. The deployed baseline passed the existing non-deploying production preflight, including the backup freshness check. Disposable Linux booted the exact sealed v0.8.1 and v0.8.2 revisions, returned to v0.8.1, and reselected v0.8.2 while checking service health, digests, and the neighboring service. The retained v0.8.2 artifact is for disposable qualification. Production staging and activation are separate.

## Authenticated visual review

The native Auth password, TOTP and OIDC scenario uses production-derived MusicBrainz evidence for `/resolution/293137` with disposable observations. It checks the pending configuration and adjacent single choices, atomic application to eight matching observations, a separate ambiguous surface, and private Archive denial after logout. The compact release-table and keyboard regressions are covered by Rails/Chromium.

- Desktop · [unchecked](desktop-resolution-unselected.png) · [checked](desktop-resolution-selected.png) · [preview](desktop-resolution-preview.png)
- Mobile · [unchecked](mobile-resolution-unselected.png) · [checked](mobile-resolution-selected.png) · [preview](mobile-resolution-preview.png)
- Mobile evidence · [ambiguous candidates](mobile-ambiguous-recordings.png) · [disputed source track](mobile-disputed-track-evidence.png)
- [Native browser result](evidence.json) · [Candidate and environment binding](binding.json) · [Sealed inventory identity](sealed-identity.json)

The full local Rails and Chromium suite passed 418 examples. The first shared browser run timed out waiting during logout. A complete rerun on the identical sealed artifact passed all nine steps, including session cookie removal and private-route denial. The [first attempt](first-browser-attempt.json) is retained for comparison.

## Signed Shell and artifact

Application Shell v2.0.0 accepted the exact candidate. [Preflight result](shell/signed-preflight.txt) · [CI report](shell/application-shell-ci.json) · [Review](shell/application-shell-review.json) · [Executable SH-08 evidence](shell/sh08-executable.json).

Sealed disposable inventory SHA-256: `b118542b843c07091a101c226a0593165c280d94951789f0a6c7f7c83418c30a`. Signed review SHA-256: `4edccb5ac9a823032f3bad4fe46bbd8381ff3e4cec51d7405329c2ea3194ae3b`.
