# Application Shell v2 adoption candidate

The candidate references Infrastructure PR #17 at `a8e02533453e63b928f81f8919ce20da51bbe087` and the Muzeum #31 handoff. The shared v2 test file retains the theme-control and release-identity fixtures from that revision (full fixture SHA-256 `8efa16791c0af1f3a96047d7d4180ac3607b333ba34bef2acc1dfcebd8bfb944`). Signed v1.3.0 remains the production contract.

Muzeum uses the **flow** header. The current surface's two approved Site Art variants are the quarry and onyx temple. Browser tests use bundled limestone and onyx fixtures plus the projected Site Art foreground fields to check pairing. SH-01 continues to use the existing geometry tests at 1440, 701, 700, 390 and 320 CSS px, including 240px-high screens. SH-06 tests the shared 44px target, safe-area-aware placement, theme persistence and single-variant suppression. SH-05 uses the existing session-binding and grant refresh regressions.

The footer can read a release-local boot-pinned `ARTIFACT_IDENTITY.json` and an artifact-keyed receipt in `shared/release-publications`. The receipt filename is the SHA-256 of the compact JSON encoding of the candidate fields sorted by name, followed by `.json`. A protected writer must verify the candidate fingerprint and independent acceptance and publication evidence, then atomically install the receipt with runtime read access. The next render reads a matching receipt without outbound requests. Previously published legacy artifacts keep the v1 marker path.

The draft minimal Capistrano adapter builds Propshaft assets into each candidate's
own release directory. After Git verification, it hashes relative paths,
executable bits, file bytes and approved runtime link names. Mutable state behind
those links and the detached identity record are excluded. Capistrano checks this
digest again before selecting an artifact. The persistent per-version ledger
uses an exclusive lock and atomically replaces the numbered history, so
a retry can retain its existing number even after the release directory is pruned.

After the existing production checks pass, the operator records acceptance in
the GitHub production deployment status for the exact candidate tuple. The
published GitHub release carries the same tuple in `muzeum-artifact.json`.
`muzeum:sync_publication[deployment,status]` verifies the successful deployment,
release tag and attachment byte digest through the operator's authenticated
GitHub CLI, then writes the artifact-keyed receipt under the Muzeum deploy
identity. The next page render observes that receipt without a network request
or service restart. Keep the receipt and corresponding artifact for rollback.

The Capistrano adapter is for disposable v2 qualification. The active
production contract is still signed v1.3.0.
