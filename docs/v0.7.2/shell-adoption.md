# Muzeum v0.7.2 Shell adoption

The baseline is published v0.7.1 at `73d06e785e4dd673f9088650b75c406fdbf2c4c3`. Muzeum selects signed Shell v2.0.0 for candidate review. The published v2.1.0 changes are scoped to Continuum. The mandatory pointer and Muzeum's adopted version remain v1.3.0 until an authorized adoption.

| Check | Candidate evidence |
| --- | --- |
| SH-01 | Sticky header with 20 px desktop and 12 px mobile link gaps, responsive navigation rows, safe-area-aware insets and visible focus. Chrome measures signed-in and anonymous geometry at the five contract widths. |
| SH-02–04 | Existing local login, account disclosure, logout and registry/grant behavior remain covered by browser and request tests. |
| SH-05 | Auth-issued username and source timestamp are stored on the local session. The conditional write rejects older and equal timestamps, even across concurrent requests. Grant failures still hide links and retain the verified label. |
| SH-06 | One shared control in both authentication states. Complete pairs expose the preference, with a single valid variant choosing the matching foreground and artwork. Chrome exercises persistence, keyboard dismissal, touch, incomplete pairs and artwork fallback. |
| SH-07 | See [release identity](shell-v2-sh07.md) for packaging, acceptance, same-process publication, and retained artifact verification. |
| SH-08 | Local browser regressions exercise public, signed-in and public-profile routes. The operator's independent rollback through the existing protected configuration still needs end-to-end rehearsal. |
| SH-09 | Schema 1 accepts both supported behavior baselines. Signed refresh and the existing verified local fallback preserve replay and tamper protection. |
| SH-10 | CI selects the signed bundle with Muzeum-owned trusted settings and uploads evidence for the exact SHA. The Capistrano acceptance path consumes the exact review and stops before opening a deployment on rejection. The audit runs the Infrastructure preflight suite against disposable signed bundles and verifies that Capistrano refuses rejected evidence before any protected phase. CI remains in audit mode while SH-08 acceptance evidence is open. |

The SH-05 migration adds two nullable columns to `sessions`. It requires the existing Muzeum-only quiescence and fresh encrypted backup and isolated recovery verification. Older builds ignore the columns. Catalog tables, grants and source observations need no backfill or rewrite.

Use the existing Infrastructure verifier with `--version 2.0.0 --adopted-version 1.3.0` and the exact review. The operator configuration sets `MUZEUM_SHELL_SELECTED_VERSION`, `MUZEUM_SHELL_ADOPTED_VERSION`, `APPLICATION_SHELL_PREFLIGHT`, and `APPLICATION_SHELL_REVIEW` outside the candidate. Preserve the existing publication checkpoint if configured. No production release number is reserved until the actual package enters the operator's existing candidate ledger.

[Browser evidence](../design/v0.7.2/README.md)
