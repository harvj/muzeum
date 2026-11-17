# Muzeum production operations

Production: https://muzeum.fm/. [Deployment/acceptance record](status.md), [canonical roadmap](../roadmap.md). Existing Auth identity only; no local passwords/registration. Last.fm is a public association, not identity proof.

## Health and import

```sh
ssh harvj 'systemctl is-active muzeum-web muzeum-worker'
ssh harvj 'sudo -n /usr/local/sbin/check-muzeum-runtime status'
ssh harvj 'sudo -n /usr/local/sbin/check-muzeum-runtime session'
curl --fail https://muzeum.fm/up
```

`status` reports a read-only repeatable-read snapshot of real counts/checkpoints; `session` reports native grant validity and timestamps, never credentials. `/up` is liveness, not a worker/database guarantee. Inspect Muzeum-only journals without printing environment files. Private dashboard statistics require a valid local session and live provider admission within the 60-second cache.

The import runs in Solid Queue on `imports`, separately from web. P1.2 continuous synchronization is active for the approved `qalephd` archive; authenticated dashboard updates appear automatically without refreshing. Resume re-enqueues the durable checkpoint. Failed imports also offer restart/replay without deleting observations. API/history drift can require a restart. Do not change an archived username manually, seed users, enable MusicBrainz resolution, or run a full real archive locally. The durable central scheduler uses bounded overlapping incremental windows and the shared one-start/second Last.fm budget. Source history/import and per-account grants remain authoritative. To stop unexpected synchronization, disable the global gate in protected configuration and restart only Muzeum; preserve all checkpoints/evidence. Do not start another historical import as a test.

## Deployment and rollback

The standing routine command is:

```sh
cap production deploy
```

Use `bundle exec cap production deploy` if the executable is not already Bundler-scoped. The command pins clean synchronized local `main`, verifies exact-SHA CI, acquires a Muzeum-only lock, checks production/credential/database readiness and detects pending Rails migrations. Its invocation authorizes reviewed ordinary additive migrations, without environment approval flags. Code-only deployment checks existing backup freshness and skips new recovery drills; migrations require matching file-hash review entries plus fresh encrypted backup/isolated four-database restoration before and after migration. Only Muzeum services/routes are controlled. The local command creates GitHub Deployment records and reports verified success/failure; Actions only runs CI. View [deployment history](https://github.com/harvj/muzeum/deployments). API outages retain nonsecret local reporting state and the independent server result; retry with `cap production 'muzeum:report[TOKEN]'`, never by rerunning a completed deployment. Full behavior, review format, failures and lock recovery: [deployment workflow](../deployment/workflow.md).

**The corrected root-owned deployment helpers are installed, hash-verified and pass non-deploying production preflight.** The first application deployment through the workflow remains operator-initiated; it was not run during installation. [Activation evidence](../deployment/finalization-2026-11-17.md). Missing/different privileged helpers fail closed. [P1.2's exact-SHA deployment](../p1.2/deployment-2026-11-17.md) used the previous guarded Capistrano process, not the new automation; its approved application SHA remains `8942bc41ae76f3c4e3d63a20552b0541c5cd3412`.

Runtime secrets remain in protected shared `.env`; migration secrets remain root-only `/etc/muzeum/migrate.env`. Migrations use `muzeum-migrate`, never runtime or superuser credentials. No production reset/drop/schema-load/seeds, automatic down migrations or automatic database restoration. P1.1 is not a compatible functional rollback target after P1.2's source-account transition. Prefer a reviewed compatible forward repair. Destructive data migrations, live restoration/cutover, credential rotation, other-app/shared-infrastructure and privileged-helper changes require separate approval.

Restoration requires matching reviewed application code and independent recovery material. Do not rotate durable keys or remove releases/gems during a recovery drill. The interpreter remains the existing root-owned read-only Ruby 3.4.12; Muzeum's bundle is separate. A failed migration retains the schema/data and stops writers; do not expose old incompatible code. A failed readiness check retains a root-only diagnostic and safe-state receipt; no deployment lock is silently expired or stolen.

First-deployment safety withdrawal:

```sh
ssh harvj 'sudo -n /usr/local/sbin/muzeum-site withdraw <current-full-sha>'
```

This validates the current revision and exact saved Muzeum-only Caddy configuration, restores original shared configuration bytes through whole-config validation/graceful reload, and stops only Muzeum services. Data/shared configuration survives. Never overwrite other sites or stop shared Caddy. Activation uses the corresponding guarded `activate` action after services/recovery gates pass. Review existing activation receipts if the route definition changes. Additive source-protection migrations deliberately refuse destructive down operations.

## Backups and recovery

The dedicated restricted Storage Box subaccount and independently encrypted Restic repository are configured in root-only `/etc/harvj-backups/muzeum/config.json`. Muzeum web/worker and all four backup timers are enabled at boot. No main Storage Box account or management credentials are used by scheduled jobs.

| Job | Schedule / manual command |
| --- | --- |
| Backup | Daily 02:00 UTC, up to 15 minutes delay; `sudo systemctl start muzeum-backup.service` |
| Full integrity | Sunday 04:00 UTC, up to 15 minutes delay; `sudo systemctl start muzeum-backup-check.service` |
| Isolated restoration | Sunday 06:00 UTC, up to 15 minutes delay; `sudo systemctl start muzeum-backup-restore.service` |
| Freshness | Hourly, up to five minutes delay; `sudo systemctl start muzeum-backup-monitor.service` |

The host backup lock serializes data operations. A refused concurrent run is not a successful backup: retry when the lock is free, without interrupting another application. Capture stops/resumes only previously running Muzeum web/worker services, dumps four databases using the SELECT-only backup role, captures storage/recovery configuration, pins repository identity, and verifies the new off-host snapshot before success. Expect a brief Muzeum maintenance pause. Required paths/provisioning are never created implicitly by a backup. Staging is private/bounded and only the validated current capture directory is cleaned.

Restoration retrieves a verified production snapshot, checks the independent manifest and every file/table fingerprint, restores only new `muzeum_recovery_<random>` databases, remaps **all four** application connections, boots the exact application read-only, and checks identity/session decryption. The strict unit keeps code/home read-only; Bootsnap writes are disabled. Only disposable targets created by the drill are removed. Primary import checkpoints are authoritative; reconcile/re-enqueue incomplete jobs after a genuine incident restore.

Healthchecks URLs/API material are root-only. Native operation failures remain failures even if monitoring is unavailable. Freshness fails after 26 hours. Retention planning is 30 daily/12 weekly/12 monthly; pruning is deliberately off. The operator's Storage Box snapshots are supplemental, not a substitute for independently recoverable Restic data.

Independent recovery material is in the operator's 1Password Document `muzeum-backup-recovery-v1.tar.gz`; retrieval was verified without echoing secrets. It contains the restricted Restic password/SSH key/host trust/repository metadata. Application/session/provider/database recovery configuration is inside encrypted production snapshots. Existing registration credentials are reused; temporary provider-side registration material is removed after successful provisioning.

For actual disaster recovery, retrieve the vault document independently, establish restricted repository access with pinned host verification, stage matching reviewed code/Ruby/dependencies, and restore into isolated replacement databases/files. Reapply only Muzeum ownership/grants and remap OS ownership. Verify source fingerprints, OIDC subject mapping, key/session decryption and fresh real provider login before traffic. **Invalidate restored RP sessions or force fresh provider checks before cutover**; an old snapshot must not resurrect revoked admission. Auth's own restoration is separate; never restore its database or another application's globals from Muzeum. Replacing production data requires explicit downtime/data-loss approval. Weekly verification never overwrites production.

## Boundaries

The administrator link stays hidden until Auth supplies trusted role evidence. Auth `/admin` continues enforcing administrator status and fresh MFA. [CE/Auth dropdown adoption](shared-session-dropdown.md) is documented only; neither application is redeployed by Muzeum's workflow. No advanced timeline, canonical MusicBrainz interpretation, recommendations or unrelated services are enabled.
