# Retire legacy Muzeum deployment machinery

This draft is for Issue #36. v0.4.0 is live at
`906a7994cb078847c403716dde4fea18288b2218`. Host changes require explicit
approval for this separate maintenance operation.
The release branch, minimal controls, recovery receipts, and existing
rollback artifact stay intact.

| Inventory | Disposition |
| --- | --- |
| Legacy root Capistrano path, config/deploy/releases.json, and revision-specific selectors | Retire. Minimal Capistrano verifies the clean tracked branch, immutable Git tree, exact CI and Shell evidence. |
| /usr/local/sbin/muzeum-deploy and its muzeum_deploy.py | Retire the entry point after all callers have moved. Preserve /var/lib/muzeum-deploy, phase lock, archived receipts and diagnostics. Keep the read-only inspector. |
| /usr/local/sbin/muzeum-migrate | Retire the helper and its sudo rule. Keep the OS identity, protected migration environment, PostgreSQL grants and operator-run migration procedure. |
| /usr/local/lib/muzeum-runtime/muzeum-service, muzeum_runtime.py, and both 20-runtime.conf drop-ins | Retire after confirming both 30-capistrano.conf drop-ins select Ruby directly. Retain the Ruby installation, locked bundle and runtime checksum manifest. |
| /usr/local/lib/harvj-backups/production_restore.py and /usr/local/sbin/check-muzeum-runtime | Keep the existing entry points and checks. Use their reviewed fixed-runtime versions before retiring the selector. Restored Rails verification requires all four database URIs to point to isolated targets and the artifact SHA to match snapshot metadata. |
| /etc/sudoers.d/muzeum and /etc/sudoers.d/muzeum-deployment | Verify these already-retired grants remain absent. Preserve operator access and the scoped Caddy helper. |
| Historic full-Caddyfile activation script | Retire the version-controlled script. If an installed copy exists, remove only after checking it has no callers and verifying scoped routing remains available. |

Leave the backup timers, escrow, encrypted repository, migration locks,
restricted accounts, routes and neighboring application services unchanged.
The historical provisioning script is a bootstrap record. Do not rerun it on
this host or use it to reset the deployment identity or permissions.

## Live dependency check

The November 22 UTC read-only inventory found both web and worker units active.
Their effective `ExecStart` uses the dedicated Ruby through
`30-capistrano.conf`, which supersedes the still-installed `20-runtime.conf`.
The four backup, restore, monitor, and check timers are scheduled.

The scheduled restore unit invokes `/usr/local/lib/harvj-backups/verify-restore`,
which takes the existing backup lock and imports `production_restore.py`.
That installed module and `/usr/local/sbin/check-muzeum-runtime` still import
the selector. Replace both in place before retiring it. The exact replacement
files used successfully during the v0.4.0 cutover have these SHA-256 digests.

```text
bd8f62230e35f10a9da767d9b956f33984cb4c2bca4daccefe0c5212f72e7e55  ops/backups/production_restore.py
d27b7323ea28f0657483db2592e9bd9f2cea4f0f8ddc0224c229662a9e3b3916  ops/provision/check-runtime.py
```

Keep the installed restore module root:root 0600 and the health command
root:root 0700. Preserve the scheduled wrapper and its systemd sandbox.
The monitor previously reported lock contention while the scheduled backup
was running. Verify freshness after the lock is released and check the next
scheduled result.

Disposable Linux qualification exercised the first v0.4.0 candidate, compatible
v0.3.6 rollback with the index retained, and subsequent promotion of the live
v0.4.0 successor without changing privileged helpers.
[Exact-head CI and Linux qualification](https://github.com/harvj/muzeum/actions/runs/44972896178).

## Separately authorized removal

1. Verify the exact live SHA, rollback directory, service health and
   neighboring PIDs. Hold the existing phase lock, and serialize with the
   backup lock. Check for an active deployment or restore. Inventory effective
   unit commands, timers, scheduled jobs and sudo policy for remaining
   references. Check `sudo -l -U` for the Muzeum deployment, runtime, and
   migration identities and validate all policy with `visudo -c`. The two named
   legacy sudoers files were absent and all three accounts had no effective
   sudo grants. Remove only a grant whose exact obsolete command is still
   present.
2. Preserve root-only copies of exact files, symlinks, ownership, permissions,
   checksums and the sudo policy. Atomically replace the existing recovery and
   health probes with their reviewed fixed-runtime versions. Verify read-only
   health and database checks before removing any executable.
3. Move only the inventoried obsolete files to the protected archive. Retain
   the separate inspector, receipt directory, both lock inodes and rollback
   artifacts. Validate sudo policy and reload systemd definitions. Verify
   loaded launch commands and unchanged service PIDs. The coordinator entry
   is a symlink to `/usr/local/lib/muzeum-deploy/muzeum_deploy.py`. Archive both
   entries while leaving the inspector in place.
4. Release the backup lock before triggering the existing
   `muzeum-backup-restore.service` because its wrapper takes that lock itself.
   Keep the deployment phase lock through verification. Confirm the latest
   encrypted snapshot is bound to the live SHA. Check the service exit status
   and the receipt's matching snapshot and release SHA, four database results,
   and application recovery proof. Check public health, Solid Queue
   heartbeats, and the next backup and restore timer times. Verify deployment, runtime and
   migration permissions independently.
5. On failure, restore the previous files and modes under the same locks,
   validate sudo and reload systemd definitions, then recheck the existing
   service and backup path. Preserve the failure record. Application rollback
   remains a separate code-pointer action on a verified compatible schema.
