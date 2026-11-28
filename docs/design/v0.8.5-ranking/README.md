# v0.8.5 release ranking eligibility

Exact successor: `5ba73ce2d636244d4bfc52953737686ec125eb2d` on `release/v0.8.5`. This includes the already-qualified visibility correction. Its [production diagnosis](https://github.com/harvj/muzeum/blob/5b45dbff49c8d28c9f603c1bc4d10805d3307ebf/docs/design/v0.8.5/README.md) records the existing UK preference, retained September US configuration, the three singles, and the eight Birthday assignments. Production remains on v0.8.4.

The former eligibility filter ran before effective-configuration membership and listening totals were computed. The artist and release detail views are the two ranking consumers. They now use each release’s effective membership to determine whether there are qualifying plays. Combined-release history cannot make another release appear eligible. The original-publication and first-publication facts retain their prior zero-play treatment. Explicit listener inclusion and exclusion remain in force.

The disposable production-derived Blur replay verifies that Leisure is admitted once and ranks first with eight distinct Birthday observations. The three admitted singles keep their zero-play rows. A separate UK-only fixture play raises Leisure’s UK total to nine. Selecting the September US configuration removes that extra observation from the release total and moves the effective date to September 24 while preserving the eight Birthday recording assignments. Retaining and selecting configurations does not alter observations, canonical identity, or publication evidence.

- [Desktop Ranked Releases](desktop-artist-ranked-leisure.png)
- [Mobile Ranked Releases](mobile-artist-ranked-leisure.png)
- [Shared browser report](evidence.json) and [binding](binding.json)
- [Exact-SHA CI](https://github.com/harvj/muzeum/actions/runs/46093002810)
- [Disposable Capistrano staging](https://github.com/harvj/muzeum/actions/runs/46093005085)

No migrations or production data repair are required.

All 418 local Rails and Chromium examples passed. Hosted CI passed on a retry of the same SHA after an unrelated Chrome document-node error in an existing system spec. The final shared native Auth run passed all ten steps. [Signed Shell v2.0.0 preflight](shell/signed-preflight.txt) · [Executable SH-08 evidence](shell/sh08-executable.json).
