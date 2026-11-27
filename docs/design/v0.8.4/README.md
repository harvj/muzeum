# v0.8.4 recording candidate highlight

The recording row uses the established pale green background and green accent in both checked and unchecked states. The native circular checkbox communicates the pending selection. The change is scoped to the reviewed recording-choice form and uses the same theme colors as the legacy row.

The Chromium system test uses the production-derived Birthday fixture at `/resolution/293137`. It checks Candidates and Evidence at desktop and mobile widths, verifies that the computed highlight persists across selection, and confirms the keyboard reveals **Resolve all 8 observations**. A separate forced-colors check verified native checkbox appearance and keyboard selection.

## Shared Auth browser review

- Desktop · [unchecked](desktop-recording-unselected.png) · [checked](desktop-recording-selected.png)
- Mobile · [unchecked](mobile-recording-unselected.png) · [checked](mobile-recording-selected.png)
- [Browser report](evidence.json) · [Artifact identity](sealed-identity.json) · [Source and environment binding](binding.json)

The shared runner used disposable native Auth and the sealed release candidate `fe77dc21efb5196378cff6a78db69411c37d93d4`. [Exact-SHA CI](https://github.com/harvj/muzeum/actions/runs/46074030082) · [Disposable Capistrano staging and rollback](https://github.com/harvj/muzeum/actions/runs/46074039168).

All 418 Rails and Chromium examples passed. The latest read-only production snapshot added assessment 299, whose candidate and release evidence matches the earlier snapshot. A supplemental disposable Chromium run confirmed both routes and forced-colors interaction with that latest assessment. [Signed Shell v2.0.0 preflight](shell/signed-preflight.txt).
