# Retire legacy Muzeum deployment machinery

This draft is for Issue #36. Install or remove nothing until v0.4.0 is live,
verified and explicitly approved for this separate maintenance operation.
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

## Separately authorized removal

1. Verify the exact live SHA, rollback directory, service health and
   neighboring PIDs. Hold the existing phase lock, and serialize with the
   backup lock. Check for an active deployment or restore. Inventory systemd,
   backup timers, scheduled jobs and sudo policy for remaining references.
2. Preserve root-only copies of exact files, symlinks, ownership, permissions,
   checksums and the sudo policy. Atomically replace the existing recovery and
   health probes with their reviewed fixed-runtime versions. Verify read-only
   health and database checks before removing any executable.
3. Move only the inventoried obsolete files to the protected archive. Retain
   the separate inspector, receipt directory, both lock inodes and rollback
   artifacts. Validate sudo policy and reload systemd definitions. Verify
   loaded launch commands and unchanged service PIDs.
4. Use the existing encrypted backup tooling to verify an isolated restore
   against the exact current artifact. Check public health, Solid Queue
   heartbeats, and backup and restore timers. Verify deployment, runtime and
   migration permissions independently.
5. On failure, restore the previous files and modes under the same locks,
   validate sudo and reload systemd definitions, then recheck the existing
   service and backup path. Preserve the failure record. Application rollback
   remains a separate code-pointer action on a verified compatible schema.
