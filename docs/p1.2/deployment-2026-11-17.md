# P1.2 production deployment — 2026-11-17

Operator explicitly authorized exact application commit `8942bc41ae76f3c4e3d63a20552b0541c5cd3412`, the guarded migration, provenance indexing and synchronization activation. Deployment used the existing Capistrano process; the newer domain/roadmap documentation commits were not included. [Exact-SHA CI passed](https://github.com/harvj/muzeum/actions/runs/44115864972).

Production moved from `ab314224abb9be1b28b01c953fe093c4bddf2e72` to the approved SHA in `/var/www/muzeum/releases/20261117155029`. The existing guarded route helper withdrew only Muzeum and stopped its web/worker before migration. It later restored only Muzeum through validated graceful Caddy reloads; Caddy itself was not restarted.

## Archive and schema

The restricted migrator applied `20261117150000`, `20261117150100`, and `20261117150200` successfully. All 97 indexes were valid/ready, constraints validated, required runtime DML present, runtime schema CREATE absent, migration/runtime roles unprivileged, and source-protection triggers enabled. [Schema receipt](evidence/deployment-schema.json).

All **292,852 original observations**, IDs 1–292852, original source payloads/fingerprints/page lineage, **1,465 raw pages**, and the completed historical checkpoint survived both migration and provenance indexing. The original observation digest remains `6fad7868cb769fb1229fa3149c4a3269c98886b7b0684f800d531d0e1b5c3041`; the raw-page manifest remains `f007312317f9131b38307578abce20d8aeef9354fd2d5ef8e6e86d21508d44cb`. Every raw checksum matched. [Before](evidence/deployment-before.json), [after indexing](evidence/deployment-after-backfill.json).

The bounded, resumable provenance task produced 1,465 page commits and 292,852 linked deliveries without changing source observations. Independent Auth-principal and historical-checkpoint fingerprints matched before/after; the session-row fingerprint also matched before intentional browser logout/re-login. No Auth identity, password, MFA enrollment, credentials or other application's data was changed.

## Fresh encrypted backup and isolated recovery

| Gate | Off-host Restic snapshot | Recovery |
| --- | --- | --- |
| Before migration | `37fc0a15c26ed8dea55e77baefcb6ec79a1d41efe97b29336489234241e67b86` | Verified 2026-11-17 15:49:47 UTC; 4 databases/11 files; exact prior app, 292,852 observations, 1,465 pages, 1 principal, 2 stored sessions; session decryption verified; 59.709 seconds |
| After migration/indexing | `f3769fd1d350266d3f08c3d382d4cf37b51a0d6562580365bcd6acc3a2f96df4` | Verified 2026-11-17 15:59:36 UTC; 4 databases/11 files; exact approved P1.2 app, same archive/principal/session counts; decryption verified; 94.207 seconds |

Pre-backup manifest SHA256: `4bdc5ca49d2c26f3f866d97641273c7c47bd5d77e991298d18e6ede789fd4847`. Post-backup manifest: `1460ec68bfb6973a20e245bc5812335b4c14599812aabd57d6ddc01f76aafc6a`. Backup capture durations were 62.762 and 111.959 seconds. Existing capture, repository identity, restricted Storage Box subaccount, encryption, independent escrow and systemd recovery services were used unchanged. Every table fingerprint matched in newly created recovery databases; only disposable targets were removed. No production restore occurred. Detailed receipts remain root-only in `/var/lib/harvj-backups/muzeum/state` and the service journal.

## Synchronization and browser acceptance

After the migrated recovery gate, enabled only `qalephd` and `LASTFM_SYNC_ENABLED=1`. The seed watermark was exactly **1794889542**, the historical run's original upper bound. The first automatic scheduler run was incremental, lower bound 1794716742, upper bound 1794931270; it imported **3 newly completed observations**, retained overlaps as repeated deliveries and excluded now-playing entries. The one-start/second budget remained intact; recorded main/boundary request starts were two seconds apart. No manual re-import or provider request was used as a test. [Persisted receipt](evidence/deployment-sync.json).

The already open authenticated Brave dashboard changed **292,852 → 292,855 without refresh**, showed synchronization active, a 13-second coverage lag at observation time, and zero failures. A subsequent automatic poll completed with zero insertions. Final read-only status at 16:27:37 UTC reported 292,856 observations, a completed latest incremental run with no error, and both Muzeum services active; the deployed SHA was unchanged. The original browser session survived deployment; local logout and fresh existing-Auth SSO/unchanged consent returned to the same archive successfully. No new account/password/MFA enrollment was required.

Muzeum, Auth, harvj.com, Arkham and the CE dashboard all returned HTTP 200 after activation. Neighboring PIDs remained unchanged: Arkham 1650983, Auth 2116532, Caddy 987, CE dashboard 2097143. Other services, code and schedules were not changed. Muzeum's existing four backup timers remain enabled; no backup scheduler was newly enabled.

## Operational interruptions and limits

The first recovery attempt correctly refused the host lock while backup was still running; it was retried after capture completed, as the runbook directs. Capistrano's initial invocation completed migration/publication/restart but failed during old-release cleanup because migrator-owned Bootsnap directories were mode 0700. Ownership was repaired only inside the obsolete release's disposable cache, then existing Capistrano cleanup succeeded. Exact-SHA/service/loopback health checks were repeated successfully after backup's intentional service pause. No code rollback or data restoration was attempted.

The operator wrapper for provenance indexing timed out after 180 seconds while its Rails child continued. That child was observed until it exited after completing all pages; no second indexer was started. Coverage checks made before indexing finished were treated as pending, and health checks made during backup's intentional pause were repeated only after service resumption. All final safety gates passed before route/synchronization activation. The proposed future workflow addresses cache ownership and bounded process-group termination; it was **not** used or installed for this deployment.

Native libvips remains absent, with variant routes disabled. The capacity/statement-budget and upstream ambiguity limitations in [performance](performance.md) and [coverage](coverage.md) remain. The previous P1.1 runtime is an incompatible functional rollback target after source-account cutover. Prefer compatible forward repair; do not reverse migrations or restore over live data automatically.
