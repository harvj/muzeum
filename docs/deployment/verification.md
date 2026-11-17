# Deployment workflow verification — 2026-11-17

Current corrected-lock/GitHub-reporting results: [finalization record](finalization-2026-11-17.md), with 157 Rails/browser examples, 32 deployment tests, and 28 backup tests. The table below retains the original preparation baseline.

The corrected root-owned helpers are installed and non-deploying production readiness passes. The first application deployment through the workflow has **not** been run. P1.2's actual exact-SHA deployment and its fresh recovery gates are recorded [separately](../p1.2/deployment-2026-11-17.md).

| Check | Result |
| --- | --- |
| [Full Rails/headless Brave suite](verification/rspec-browser.txt) | 140 examples, 0 failures; isolated PostgreSQL 16 database; existing OIDC, archive grants, ingestion, dashboard Turbo updates, and seven new Git/CI revision-guard examples |
| [Disposable deployment/recovery suite](verification/deployment-tests.txt) | 25 tests, all passed; real four-database PostgreSQL dumps/restores, local encrypted Restic repository/read-data checks, Rails additive migration, source/principal/decision fingerprints, full application schema/restricted-role inspector, timeout process groups and failure boundaries |
| Existing backup/recovery suite | 28 tests, all passed |
| [RuboCop](verification/rubocop.txt) | 146 files, no offenses; final inspector changes also linted independently |
| [Brakeman](verification/brakeman.txt) | 0 errors, 0 security warnings |
| [Refreshed dependency audit](verification/dependency-audit.txt) | No vulnerabilities |
| Capistrano configuration | `bundle exec cap production -T` loaded successfully without server contact; an attempted dry-run was refused by the dirty-checkout guard before any server deployment action |

Local database tests used a dedicated PostgreSQL 16 cluster on loopback port 56527, only disposable `muzeum_deploy_test_*` targets and synthetic fixtures. The actual inspector booted Rails against four isolated full schemas under a DML-only fixture role; missing grants, disabled source triggers and stale worker heartbeats were refused. Cache/cable schema bootstrap version anchors were tested explicitly.

The routine code-only path published the fixture release, restarted/verified the fixture services and completed without capture, recovery, migration or route withdrawal. The additive path ran a real Rails `add_column`, verified original source/principal/interpretation rows, performed encrypted four-database isolated recovery before and after, then restored fixture availability. Further tests used a real failed Restic subprocess, a real failed Rails transaction, and failure after a committed migration; all preserved existing source data, stopped safely, retained audit locks and never reversed committed schema.

Publication, service restart/readiness and Caddy activation faults use a disposable filesystem/service adapter. They verify the actual phase state machine, not a live remote systemd/Caddy installation. Dirty/ahead/behind/diverged/detached Git states are real temporary repositories; GitHub CI responses are controlled fixtures. These results are preparation for the required separate safety/installation review, not a claim that the new `cap production deploy` has been run successfully against production. CI repeats the full suites, including the disposable database/Restic checks, on the committed revision. Its database job uses Ubuntu 24.04 and fixture client tools explicitly pinned to PostgreSQL 16 to match the server instead of relying on hosted-runner client defaults; synthetic failures include their retained fixture diagnostic.
