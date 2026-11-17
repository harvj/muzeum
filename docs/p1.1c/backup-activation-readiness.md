# Backup activation readiness

> Historical P1.1c checkpoint. Production backup activation, independent vault retrieval and actual identity/history/session restoration are now recorded in [P1.1d acceptance](../p1.1d/status.md) and the [current operations runbook](../p1.1d/operations.md).
## Current verification

The earlier authentication blocker is resolved. Following [Hetzner's documented port-23 OpenSSH key method](https://docs.hetzner.com/storage/storage-box/ssh-keys/add-ssh-keys/), the dedicated public key was installed through the authenticated main Storage Box account at `applications/muzeum/.ssh/authorized_keys`. The file was absent; existing-byte preservation and duplicate-key checks were performed before upload, followed by byte-for-byte readback. `.ssh` is mode 0700 and `authorized_keys` mode 0600. No other account's keys were changed.

The private key remains `/etc/harvj-backups/ssh/muzeum-ed25519`, root-owned, mode 0600. Verified fingerprint: `SHA256:VbDWXuK0R6e8/zl70tRtoPr5rqJzr781hFVevNo1l40`. No private key or repository password was transmitted or printed.

Key-only SFTP authentication to `u720116-sub1@u720116.your-storagebox.de:23` succeeded with strict pinned host verification. Disposable markers proved that its `/home` maps bidirectionally to the main account's `applications/muzeum`. Six parent/sibling traversal reads of outside markers were denied. Both test rounds' markers were cleaned up. An initial test treated `/../home/<inside-marker>` as outside; that path actually resolves to the same confined home. The corrected test used distinct inside/outside names and passed. Existing applications' repositories were not read or modified. This is behavioral filesystem verification, not a Console/API inspection of account metadata.

The same existing encrypted repository was opened using only the restricted key, preserving the independent encryption password. Repository ID: `76a36c7d3bd30fe1fd6d242f55a5f2adc7a43b3c7d978ecd2974c4f0a808bb51`. No new initialization was necessary. Its restricted view is `sftp:u720116-sub1@u720116.your-storagebox.de:/home/restic`.

The helper's hostname allowlist now accepts the verified main endpoint as well as the subaccount alias; strict host verification remains required. The updated helper is installed, and a root-only manual profile is at `/etc/harvj-backups/muzeum/subaccount-readiness.json`. This is disposable readiness capture, not production configuration. Ten focused local tests passed.

Restricted-account verification:

* Backup: snapshot `d2bfba122e123d0601229949f90ddee659da7ff0463c3db75050bacfeb5ead62`, 23.453 seconds; expected host/path/tags read back before Healthchecks success. Start and success acknowledged with run ID `8fe9cff5-0f8e-4b11-9940-cf3a9b91b6e0`.
* Restore: 11.083 seconds; four file hashes, 1,000 rows and two indexes verified; row checksum `2f065cb6e35689f056013bf9319cc069`. Newly created disposable database `muzeum_backup_restore_442c89d60cb3` removed after verification.
* Full encrypted-data integrity check: `restic check --read-data` passed through the restricted account in 59.958 seconds, exit 0.

Separate restoration/verification URLs were absent during these restricted recovery tests. They have since been created and securely wired; see [management verification](healthchecks-management.md). No new pings have yet been sent to these checks. During the earlier tests, missing URLs were logged (`KeyError` category); data-operation results were preserved. No new email delivery claim is made; prior recipient-confirmed failure/missed-run delivery evidence remains in `healthchecks-live-verification.md`.

All four backup timers remain **disabled**. Earlier `systemd-analyze verify` of the backup service/timer exited 0 with unrelated existing Continuum oneshot RuntimeMaxSec warnings. `/etc/harvj-backups/muzeum/config.json` remains absent. Manual transient tests used resource limits, private temporary storage and the host backup lock. No timer was enabled.

## Production capture contract — not activated

The existing adoption template remains disabled, and the installed helper rejects production mode. These are deliberate fail-closed gates. Production capture implementation and activation must follow verified provisioning; this report does not claim it is already operational.

* Databases: `muzeum_production`, `muzeum_production_cache`, `muzeum_production_queue`, `muzeum_production_cable`. Verify each exists, is owned by the intended Muzeum owner, and has the expected schema/migrations before capture. Never create a missing database from a backup job.
* Roles: the deployment plan defines `muzeum_owner`, `muzeum_migrator` and `muzeum_runtime`; it does not yet approve a dedicated backup role/grant script. Review a separate read-only `muzeum_backup` login with CONNECT on only these databases, schema USAGE and SELECT/default SELECT privileges for every object-creating role. No superuser, cluster-wide pg_read_all_data, CREATEDB, CREATEROLE or migration credentials for scheduled dumps. Validate RLS and sequence access where applicable. Scope connection rules and limits during provisioning. Credentials belong in a root-only password file, outside Git/application paths and command arguments.
* Files: capture `/var/www/muzeum/shared/storage`, shared `.env` and `.env.migrate`, actual Rails credential/session recovery material, release SHA, schema/migration versions and scoped grant/recovery instructions. Verify concrete secret locations without printing contents. Reject missing required paths and unexpected symlink traversal. Existing application paths are outside this allowlist.
* Consistency: coordinate only Muzeum web writers, enqueuers and Solid Queue workers before four custom-format pg_dump captures and the storage copy. Record prior service state and resume only previously running Muzeum services on failure/success. Four individually consistent dumps are not a single atomic cross-database snapshot. This interruption procedure requires deployment approval and a tested recovery path before activation.
* Staging: root-owned 0700 per-run directories, 0600 dumps, bounded disk/CPU/memory/I/O and exclusive job lock. Use failure-safe cleanup of only the current job's validated staging directory after verification; preserve required failure diagnostics without secret contents. Never recursively clean an unvalidated configured path. The current readiness helper retains bounded fixture captures; production cleanup is still to implement/test.
* Completion: verify the expected repository ID and newly created snapshot's application/production tags, host and captured paths before reporting Healthchecks success. Preserve native backup errors if monitoring fails. Keep separate integrity/restoration conditions; provision separate checks for those jobs.

## Remaining activation gates

1. Restricted key authentication, confinement and disposable recovery are verified. Keep the main account out of scheduled Muzeum profiles; preserve the current repository identity and independent encryption credentials.
2. Approve/provision Muzeum-only users, roles, four databases, files and runtime through the separate deployment workflow. Implement and test the capture contract above, including staging cleanup and writer resumption failures, without making missing provisioning implicit.
3. Independently escrow repository encryption/recovery material; verify recovery without relying on the dedicated server. Separate verification/restoration checks are now configured; complete genuine job signaling verification before claiming their live notification coverage.
4. Perform production-compatible isolated recovery and then the first real production capture once approved provisioning exists; record durations, snapshot and integrity evidence.
5. Obtain explicit approval before enabling timers. Retention remains 30 daily/12 weekly/12 monthly; destructive pruning remains off until the restricted recovery gate passes. Ten daily Storage Box snapshots are additional user-managed protection, with management credentials kept off this server.

Backup preparation can accompany reviewed production provisioning, but **production backup activation is blocked**. No production databases, Caddy changes, deployments, pushes, timer activation, pruning or changes to other applications were performed. Additive operational changes were the Muzeum authorized-key file/directory, the helper hostname correction, the manual readiness profile, transient resource-limited test units and sanitized verification state/captures/restores.
