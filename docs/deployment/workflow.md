# Muzeum single-command deployments

Standing operator convention: **`cap production deploy`** (equivalently `bundle exec cap production deploy` when Bundler is needed). Invoking it authorizes deployment of the reviewed, synchronized local `main` and execution of its reviewed additive migrations. No environment flags or interactive secret prompts are required. Agents still need explicit authorization to invoke a production deployment; implementing code does not imply that authorization.

**Finalization is in progress: corrected helpers and local GitHub reporting are being verified before installation.** P1.2 was deployed separately through the previous process: [production record](../p1.2/deployment-2026-11-17.md). The operator remains responsible for the first production deployment; helper installation and non-deploying preflight are separate from publishing application code. It refuses a missing/different installed helper. CI never deploys.

## Normal behavior

1. Require clean local `main`, including untracked files, tracking `origin/main` in `harvj/muzeum`. Fetch with noninteractive SSH and require exact equality; refuse ahead/behind/diverged/detached states. Require the latest `CI` run for that exact commit to have passed. Pin that immutable SHA for Capistrano's Git archive.
2. Verify the installed root helper and inspector match the local reviewed bytes. Acquire a persistent Muzeum-only deployment lock and create an independently retained root-only receipt under `/var/lib/muzeum-deploy/<token>.json`. A second invocation or crash never steals the lock.
3. Check protected credentials/configuration, root-owned helpers, existing independent recovery escrow, existing backup freshness (the established 26-hour limit), disk headroom (the established 8 GiB recovery allowance), service/loopback health, all four database connections, restricted roles/grants, valid indexes/constraints, source triggers and native Solid Queue process heartbeats. Refuse legacy migrator-owned Bootsnap caches before modifying a release. Use the existing host backup lock to exclude scheduled backup pauses during each guarded phase; contention fails safely rather than treating a refused backup as success.
4. After preflight, create the native GitHub Deployment and `in_progress` status locally, correlated by SHA/token with the server receipt. If initiation reporting fails, cancel untouched server preparation without withdrawing/restarting services. Then let Capistrano prepare the exact release, link shared configuration, install the locked bundle and build assets. Inspect pending Rails migrations across primary/cache/queue/cable. Require an exact matching review entry for each pending file.
5. For **code only**, retain public availability through preparation, skip fresh capture/recovery drills and migrations, publish, restart only Muzeum web/worker, and verify readiness. The normal systemd restart can briefly interrupt Muzeum requests; no new rolling-service infrastructure is introduced.
6. For **migrations**, withdraw only Muzeum through the existing guarded route helper and stop its writers. Take and isolated-restore-verify a fresh encrypted four-database backup against the old release. Fingerprint every existing application table's original columns under the SELECT-only backup role, including observations, provenance, identities and interpretation history. Exclude only Rails migration/internal metadata.
7. Invoke the existing restricted migration OS/database identity; never run migrations with runtime credentials or as PostgreSQL superuser. No reset, seeds, schema replacement on populated databases, down migrations or automatic database restoration. Read-only inspection refuses uninitialized auxiliary databases. The retained migrator's empty-database bootstrap is therefore unreachable in routine deployments. Migrations have a 5-second lock timeout, 120-second statement timeout and bounded process groups; a timeout terminates descendants before returning failure.
8. Before publishing, require no pending migrations, valid schema/indexes/constraints/runtime grants, unchanged original-column fingerprints and unchanged existing source-trigger definitions/functions, index definitions and constraints. Added columns/tables/indexes are allowed; data rewrites or weakened existing protections require a separate procedure.
9. Publish the exact prepared release, restart only Muzeum, and check services, `/up`, database reads and native Supervisor/Dispatcher/Worker/Scheduler heartbeat freshness using Solid Queue's own `process_alive_threshold`. Bounded retries allow normal process startup. For migrated deployments, take another fresh encrypted backup and verify isolated four-database restoration against the published SHA before restoring the public route.
10. Finish Capistrano cleanup, reverify health/current release, retain the completed receipt, then release the deployment lock. Output SHA, migration inventory, backup/recovery references, service verification and outcome. Only after the server records `complete` with passed health, publish GitHub `success` from the local command. A failed attempted deployment reports `failure`; cancelled initiation reports `error`. Releases, migration versions and off-host backup snapshots remain separate audit records.

The helper uses the **installed existing** backup/recovery implementation and the same host lock, repository, protected credentials, escrow, monitoring and scoped databases. It does not provision infrastructure, rotate keys, change timers, or restart CE/Auth/shared Caddy. The existing route helper may validate and gracefully reload Caddy while preserving every other site block. Old releases remain subject to Capistrano's five-release retention.

## Reviewing an additive migration

Add a reviewed entry to `config/deploy/migrations.json` in the same change as the migration:

```json
{
  "format": 1,
  "migrations": {
    "db/migrate/20261118000000_add_operator_note.rb": {
      "sha256": "<sha256 of the exact reviewed file>",
      "risk": "additive",
      "quiesce": true,
      "review": "<review reference and lock/data-impact assessment>"
    }
  }
}
```

This is a review declaration, **not a static proof that arbitrary Ruby is safe**. Review SQL, lock impact, forward compatibility, runtime grants, source/interpretation preservation, expected duration, concurrent-index failure handling and new schema expectations. All routine migrations use Muzeum-only quiescence and fresh before/after restoration; the deliberate small design avoids per-migration runtime flags and risk-class engines. Use additive schema changes; ship substantive data backfills as separately reviewed bounded work. Hash changes invalidate approval. Already applied historical migrations need no new entry. Cache/cable/queue bootstrap schema version anchors are recognized explicitly; unknown database migration versions are refused.

Destructive/irreversible data migrations, live restoration/cutover, credential rotation, changes to other apps/shared infrastructure, and changes to this privileged helper require separate review/authorization. They cannot be enabled by changing an environment flag or declaring `risk: destructive`.

## Failure recovery without losing data

Every failure retains `active.json`, the token receipt, failed phase, migration intent and safe-state diagnosis. Sensitive subprocess stderr is bounded and root-only in `command-last-error`; migration detail is root-only `/etc/muzeum/migration-last-error`. Never paste protected diagnostics/environment files into public logs. Helper stdout contains references/status only. A disconnected client may leave a phase running: inspect process groups, the phase lock, database activity, service/route state and receipts before taking action.

| Failure | Expected safe state and operator action |
| --- | --- |
| Dirty/diverged checkout, missing CI/helper | Refused before server deployment. Fix checkout/CI or complete the separately reviewed helper installation. |
| Preflight/host backup-lock contention | Prior application retained; root receipt/lock retained if acquisition began. Wait for the existing backup job, inspect its result and prior application health, then archive the deployment lock before a new invocation. Never interrupt another application's backup. |
| Build or publication failure before migration | Prior release normally remains public/running. Check exact `current` target. If publication switched releases before failing, the helper withdraws/stops Muzeum; diagnose the candidate rather than automatically rolling back. |
| Backup or isolated recovery failure | No migration after a failed pre-backup gate. Muzeum remains withdrawn/stopped once migration preparation began; old data/releases remain. Diagnose repository, disk, credentials and protected receipts; independently verify recovery before resuming. A post-backup failure leaves the new schema/release stopped and preserves all live data. |
| Migration failure/timeout | Route withdrawn, writers stopped, lock retained. Inspect committed versions, active SQL/process groups, invalid concurrent indexes and protected diagnostics. Never assume transactional rollback or that nothing committed. Repair forward with a reviewed compatible candidate; index-only repair needs review. No `db:rollback`, source reset or automatic P1.1 fallback. |
| Source fingerprint/schema/grant failure | Keep route/writers off. Preserve evidence and backups, compare exact original columns/triggers, and review forward repair. Do not normalize the failed receipt or bypass the gate. |
| Restart/readiness/activation failure | Withdraw only Muzeum where possible and stop its services, retaining the published candidate and data. Inspect Muzeum journals, loopback/DB readiness, worker heartbeats and credentials; use a compatible forward fix. If guarded route withdrawal itself refuses changed shared Caddy bytes, services are still stopped and the receipt calls for manual route inspection; never overwrite shared configuration. |
| Cleanup failure | Deployment stays incomplete/locked; the failure hook stops the new candidate. Inspect the exact release/cache ownership; repair only disposable Muzeum cache permissions after review. Never recursively change protected shared configuration ownership. |
| Client crash/SSH loss | No automatic lease expiry or rollback. Verify whether the root phase is still executing; finish or safely withdraw only Muzeum under operator control, retain all data, and reconcile migration/recovery receipts before a new attempt. |

To retry, an authorized operator must first establish no phase/migration/backup process remains, reconcile `current`, schema versions, source integrity, public route and writer state, and preserve the token receipt. Under the root phase lock, **archive rather than delete** `active.json` with an operator recovery reference. No unlock task or timeout silently approves this decision. Restore a verified compatible Muzeum service state using the existing manual runbook helpers, or complete a separately reviewed forward repair; then rerun the clean synchronized command. Actual restoration over production still needs separate explicit downtime/data-loss approval and isolated replacement targets. Do not restore an older snapshot over live data.

## Installation review

Review `config/deploy.rb`, `lib/muzeum_deployment_revision.rb`, `ops/deploy/muzeum_deploy.py`, `ops/deploy/inspect.rb`, and `ops/provision/muzeum-migrate` together. Verify the existing production backup modules/services and restricted identities match assumptions. Rehearse on a disposable host if service/Caddy behavior has changed. Resolve legacy Bootsnap ownership only inside identified disposable release caches; preserve shared credentials, data and recovery material.

After the authorized focused safety review, install the coordinator and inspector as root-owned, non-writable files in `/usr/local/lib/muzeum-deploy/`, expose `/usr/local/sbin/muzeum-deploy` as a root-owned symlink to the coordinator, update the root-owned restricted migration helper, and grant the Muzeum deployment identity only `sudo -n /usr/local/sbin/muzeum-deploy *`. The coordinator validates phase/SHA/token/release boundaries and only controls Muzeum. Do not run application code as root. Its Rails inspector executes as `muzeum`; migrations execute as `muzeum-migrate`; fingerprints use `muzeum_backup`. Create no new credentials or scheduler. The version handshake covers both installed coordinator and inspector bytes; migrations additionally check the installed migrator against the reviewed candidate bytes. The command deliberately cannot self-install or update privileged helpers. The root `preflight` action holds the existing backup lock and invokes the installed backup API's freshness action directly; it never launches the CLI that would reacquire the same lock. `receipt SHA TOKEN` exposes only nonsecret outcome fields. `cancel SHA TOKEN` is restricted to unchanged preparation before any deployment/migration and retains the cancelled receipt while releasing the application lock.

## GitHub tracks deployments; local Capistrano performs them

View production history at [GitHub deployments](https://github.com/harvj/muzeum/deployments). The operator's existing authenticated `gh` CLI calls the [native Deployments API](https://docs.github.com/en/rest/deployments/deployments) and [deployment statuses API](https://docs.github.com/en/rest/deployments/statuses). No GitHub token, API client, or reporting credential is installed on production. CI remains push/pull-request verification only; no Actions deployment trigger is added.

Creation uses the full immutable SHA, `auto_merge: false`, `environment: production`, and an empty required-context list because the local command has already verified the latest exact-SHA CI result. Status descriptions contain only the short SHA and verification/outcome summary; the environment URL is `https://muzeum.fm`. Payload contains the nonsecret token and receipt basename, allowing correlation with `/var/lib/muzeum-deploy/<token>.json`. Backup references, recovery material, protected diagnostics and credentials stay out of GitHub.

The local outbox lives in `<git-common-dir>/muzeum-deployments/`, with mode-0600 per-token records and a local reporting lock. It is not tracked by Git and does not dirty the checkout. The server's persistent application lock serializes actual deployment attempts, including operators using different checkouts. API calls are bounded to 30 seconds. The actual server result is retained independently of reporting; post-success reporting failure never invokes rollback, service withdrawal or the failure hook. It prints an explicit pending-report warning. Resolve pending reports before a new deployment, so an old delayed success cannot overwrite a newer attempt's history.

Retry only publication, without rebuilding, migration, backup, restart or redeployment:

```sh
cap production 'muzeum:report[<32-character-receipt-token>]'
```

Retry reads the authenticated server receipt and derives status from it. Published/verified-but-not-complete phases remain non-success and incomplete attempts stay visibly pending. A lost status response is reconciled by reading the latest status before posting; matching states are not duplicated and contradictory terminal states (including externally retired/inactive deployments) are refused.

GitHub does not supply a create-idempotency key. Persist creation intent before POST and use a unique token in the deployment payload. After an ambiguous create response, retry **lookup only**: reuse the matching record, reject multiple matches, and never blindly create another record if lookup cannot yet confirm whether the first request was accepted. Such an uncertain attempt requires later lookup or explicit operator reconciliation; do not delete/reset the outbox or clear a server lock merely to bypass it. If an outage occurred before a create request was submitted, normal retry may safely create the cancelled attempt's record and publish `error`. This deliberate fail-closed case prevents duplicates without inventing an exactly-once API guarantee.

Optional non-deploying operator check:

```sh
cap production muzeum:preflight
```

It validates clean synchronized local main/CI, the version handshake and production readiness without creating a GitHub Deployment, acquiring a persistent deployment attempt, running migrations or publishing/restarting a release.

## Reproduction and limits

Use a dedicated disposable PostgreSQL cluster and fixture credentials only:

```sh
MUZEUM_DEPLOY_TEST_PGPORT=<isolated-port> \
MUZEUM_DEPLOY_TEST_PGBIN=<postgres-bin-directory> \
MUZEUM_DEPLOY_TEST_RESTIC=<restic-binary> \
python3 -m unittest discover -s ops/deploy -p 'test_*.py' -v
bundle exec rspec spec/operations/deployment_revision_spec.rb
bundle exec cap production -T
```

Fixtures create only `muzeum_deploy_test_*` databases, synthetic observations/raw pages/OIDC principals/interpretation decisions, and production-named restricted roles in the **dedicated disposable cluster**. The inspector fixture refuses a cluster already containing those roles. Real PostgreSQL, Rails migrations, Restic encryption/read-data checks, four-database isolated restores and full application schema inspection run locally and in CI. Service restart, publication faults and Caddy boundaries use a disposable filesystem/service adapter, not production systemd/Caddy. These tests do not replace the required separate installation review or claim a second live production deployment. Never use a production port/URL. Retained verification results: [verification](verification.md).
