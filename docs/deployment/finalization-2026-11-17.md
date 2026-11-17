# One-command deployment finalization — 2026-11-17

The operator owns the first `cap production deploy`. This work does not redeploy P1.2, run production migrations, create test scrobbles or create a GitHub release. P1.2 remains at `8942bc41ae76f3c4e3d63a20552b0541c5cd3412`.

## Corrections and verification

The committed nested host-lock failure is fixed by calling the installed backup API's existing `do_action(config, 'monitor')` while the coordinator owns the host lock. The standalone backup CLI retains its unchanged lock acquisition. Regression tests execute the original CLI lock path under contention, verify direct action success without releasing serialization, and verify contention and failure cleanup. No new locking framework or weakened lock is introduced.

The local GitHub outbox correlates native Deployment records with exact SHA/server receipt token. Capistrano task fixtures exercise initiation, cancellation, successful completion, health failure, post-success API failure and reporting-only retry. Reporting fixtures additionally cover lost create/status responses, token lookup, duplicate prevention, contradictory/retired statuses and incomplete receipts. The production API was read only: existing CLI authentication has repository scope and push/admin permissions; native Deployments listing succeeded. No fake production deployment was created. First real lifecycle publication belongs to the operator's first real deployment.

Local results: **157 Rails/headless Brave examples**, **32 deployment/recovery/lock tests**, and **28 backup tests** passed. Lint: 151 Ruby files, no offenses. Brakeman: zero errors/warnings. Refreshed dependency audit: no vulnerabilities. Four-database recovery uses real isolated PostgreSQL 16, real Rails additive migrations, encrypted Restic repositories and source/principal/interpretation fixtures. Service/Caddy boundaries and GitHub requests are controlled fixtures. [Retained logs](verification/finalization/rspec-browser.txt), [deployment tests](verification/finalization/deployment-tests.txt), [lint](verification/finalization/rubocop.txt), [security](verification/finalization/brakeman.txt), [dependencies](verification/finalization/dependency-audit.txt).

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

Initial helpers from `a2648ab69721f799db478924f6756e0d9f93c587` were installed at 17:48:04 UTC after [exact-commit CI passed](https://github.com/harvj/muzeum/actions/runs/44140168133). The version handshake and narrow sudo rule passed, but non-deploying preflight correctly stopped on an inspector command lookup: its deliberately restricted PATH excludes `/usr/sbin`, so relative `runuser` was not found. The correction uses `/usr/sbin/runuser` explicitly; a regression test exercises the constrained environment and the real executable on Linux. No PATH expansion, privilege change, check bypass, service restart or application publication was used. The corrected coordinator was subsequently installed after [its CI passed](https://github.com/harvj/muzeum/actions/runs/44141383425); final readiness below completed after the native-label correction. No production deploy command has been executed.

The next non-deploying check identified an inaccurate supervisor label in the inspector fixture: Solid Queue 1.7.2 registers `Supervisor(fork)`, not `Supervisor`. Production supervisor/worker/dispatcher/scheduler heartbeat ages were all two seconds. The inspector now derives `Supervisor(<configured mode>)` from the locked library configuration, retaining the native freshness threshold and all required process checks. Disposable tests seed the actual native label and reject the invented plain label. No production queue or service change was required.

## Active installation and handoff

The final reviewed helper bytes come from `f3e82530349d03bdf15385940a6de470a0581872`; [all CI jobs passed](https://github.com/harvj/muzeum/actions/runs/44143009147). Subsequent handoff/logging/documentation changes do not change these helper bytes. The combined coordinator/inspector handshake is **`c8f9ef31aecf4922bfc71a934d0a1b55865e7a58c2b6876a8a8e0d8e0071d87b`**.

| Installed file | Owner / mode | SHA256 |
| --- | --- | --- |
| `/usr/local/lib/muzeum-deploy/muzeum_deploy.py` | root:root / 0700 | `d2e1684dd69791699d8c5790e96e445f859933ec1116584a181ddabd471eb135` |
| `/usr/local/lib/muzeum-deploy/inspect.rb` | root:root / 0600 | `a3ca9063f5d1dc8ebbf9e26b57ab0db0b062df5b34468b54125490a43a420c78` |
| `/usr/local/sbin/muzeum-migrate` | root:root / 0700 | `5b9f9855e8bc63b9889b49c30773f91b946c353ae2a71e891fde7e1e92d2ee65` |

`/usr/local/sbin/muzeum-deploy` is a root-owned symlink to the coordinator. Its directory is root-only; runtime cannot alter any helper. The existing migration helper was archived under `/etc/muzeum/` before atomic replacement. A validated root:root/0440 `/etc/sudoers.d/muzeum-deployment` adds only `muzeum ALL=(root) NOPASSWD: /usr/local/sbin/muzeum-deploy *`; existing Muzeum migration/restart grants and all other sudo policies are unchanged. `visudo -c` passed.

The restricted deployment identity's CLI version handshake/preflight passed, and the protected readiness receipt reconfirmed success at **18:06:54 UTC**: existing encrypted backup freshness and four-database recovery receipt, protected configuration/escrow, disk, service/database reads, runtime/migration-role restrictions, indexes/constraints, source protections and native process heartbeats. No deployment attempt or active deployment lock was created. Protected detailed receipts are `/var/lib/muzeum-deploy/installation-20261117.json`, `installation-update-20261117.json`, `installation-final-20261117.json`, and `installation-preflight-20261117.json`. Backup/recovery detail stays in those server receipts; GitHub Deployment payloads receive only nonsecret correlation and outcome information.

A final read-only preservation check matched all original 292,852 observations and 1,465 raw pages, the original source/raw manifest digests, Auth principal mapping and historical checkpoint. No production scrobble was fabricated or historical row modified. All 56 pre-existing service/timer/Caddy/sudo configuration hashes remained identical; only the one Muzeum-specific sudo file was added. Muzeum, Auth, Arkham and Caddy PIDs remained unchanged. CE's dashboard showed separate restart activity during the window; this task issued no CE restart or code/configuration changes, its unit hash stayed unchanged, and its endpoint remained HTTP 200. Other checked public endpoints also returned 200. Existing backup timers and libraries were unchanged; all inspected locks were free. All 12,313 inspected regular cache files had link count one, ruling out ownership changes through hard links outside the disposable caches.

The complete local Capistrano readiness check also exposed an unsupported top-level `info` logger call before any server operation. It now uses standard Ruby output; the real preflight and deployment task fixtures no longer replace logging methods, and reporting-outage tests assert the visible retry warning. No new server privileges or safety bypass was needed.

Operator commands after pulling the current clean synchronized main:

```sh
git pull --ff-only
cap production deploy
```

No routine environment flags, migration assembly or secret prompts. Optional `cap production muzeum:preflight` performs readiness only. Successful deployment prints the immutable SHA, a completed server verification/receipt and `GitHub deployment <id>: success`, linked to `https://muzeum.fm` in [native deployment history](https://github.com/harvj/muzeum/deployments). If only reporting fails after verified success, follow the printed `muzeum:report[TOKEN]` retry, not another deployment. Ambiguous create responses deliberately require lookup/manual reconciliation before a new attempt rather than risk duplicate records.

**No first production `cap production deploy`, release, P1.3 work, schema migration or P1.2 redeployment was performed.** GitHub reporting lifecycle/transport failures were tested with fixtures; no synthetic production Deployment record was created. The operator's real deployment will be the first live lifecycle write.
