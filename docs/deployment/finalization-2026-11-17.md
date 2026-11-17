# One-command deployment finalization — 2026-11-17

The operator owns the first `cap production deploy`. This work does not redeploy P1.2, run production migrations, create test scrobbles or create a GitHub release. P1.2 remains at `8942bc41ae76f3c4e3d63a20552b0541c5cd3412`.

## Corrections and verification

The committed nested host-lock failure is fixed by calling the installed backup API's existing `do_action(config, 'monitor')` while the coordinator owns the host lock. The standalone backup CLI retains its unchanged lock acquisition. Regression tests execute the original CLI lock path under contention, verify direct action success without releasing serialization, and verify contention and failure cleanup. No new locking framework or weakened lock is introduced.

The local GitHub outbox correlates native Deployment records with exact SHA/server receipt token. Capistrano task fixtures exercise initiation, cancellation, successful completion, health failure, post-success API failure and reporting-only retry. Reporting fixtures additionally cover lost create/status responses, token lookup, duplicate prevention, contradictory/retired statuses and incomplete receipts. The production API was read only: existing CLI authentication has repository scope and push/admin permissions; native Deployments listing succeeded. No fake production deployment was created. First real lifecycle publication belongs to the operator's first real deployment.

Local results: **156 Rails/headless Brave examples**, **30 deployment/recovery/lock tests**, and **28 backup tests** passed. Lint: 151 Ruby files, no offenses. Brakeman: zero errors/warnings. Refreshed dependency audit: no vulnerabilities. Four-database recovery uses real isolated PostgreSQL 16, real Rails additive migrations, encrypted Restic repositories and source/principal/interpretation fixtures. Service/Caddy boundaries and GitHub requests are controlled fixtures. [Retained logs](verification/finalization/rspec-browser.txt), [deployment tests](verification/finalization/deployment-tests.txt), [lint](verification/finalization/rubocop.txt), [security](verification/finalization/brakeman.txt), [dependencies](verification/finalization/dependency-audit.txt).

## Narrow production cache repair

Before any ownership change, all entries in exactly these directories were verified as regular Bootsnap cache files/directories, with no symlinks or special files:

- `/var/www/muzeum/releases/20261117040737/tmp/cache/bootsnap`
- `/var/www/muzeum/releases/20261117042253/tmp/cache/bootsnap`
- `/var/www/muzeum/releases/20261117040115/tmp/cache/bootsnap`
- `/var/www/muzeum/releases/20261117134059/tmp/cache/bootsnap`
- `/var/www/muzeum/releases/20261117155029/tmp/cache/bootsnap`

At **17:31:16 UTC**, `fchown` changed only **426 migrator-owned cache entries** to `muzeum:muzeum`, through verified no-follow file descriptors/inodes. File modes and content hashes were preserved. The remainder of the release trees, shared storage, credentials and database files were untouched. The initial validation recognized the standard `load-path-cache` after checking the installed Bootsnap source; no ownership change occurred before complete validation. Root-only receipt: `/etc/muzeum/deployment-cache-repair-20261117.json`; changed-entry manifest SHA256 `25b0a370d96b3346ad99d236d6d4670a4c32fb66a47153533fa61df23cb17368`.

Muzeum web/worker PIDs remained 2185922/2185927; HTTPS `/up` returned 200. Automatic synchronization continued naturally; no observation was created by the repair or its verification.

## Installation gate

Corrected helper installation is pending exact-commit CI and the final production assumption/hash checks. Completion evidence will be recorded here after installation. No production deploy command has been executed.
