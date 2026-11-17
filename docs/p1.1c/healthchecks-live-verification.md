# Healthchecks.io live integration verification

Later restricted-account authentication, isolation and recovery verification is recorded in [backup activation readiness](backup-activation-readiness.md); the bootstrap-only limitations below describe the earlier test session.

Verified 2026-11-16 UTC (2026-11-15 America/Chicago). Project `harvj-backups`; daily check `Muzeum — Daily Backup`; intended email `jimrharvey@gmail.com`; owner-configured 24-hour interval and two-hour grace. The ping URL was read only from `/etc/harvj-backups/muzeum/monitoring.json`, root:root 0600, and was never printed, passed in argv/environment, put in Git or included in this report. No management API credential or SMTP relay was used.

## Results

| Test | Evidence / result |
| --- | --- |
| Live backup success | Genuine disposable backup exited **0**, snapshot `116e660c91596c14e59e34b363bff692ebb897f28619fbc33fe3f30cf74be231`; repository identity and snapshot hostname/path/tags read back before acknowledged success. Data operation 20.327 s, service 21.335 s |
| Deliberate backup failure | Separate wrong-password profile failed at repository access with **native Restic exit 12**; matching start/failure run ID `803fed1c-e0b8-4dda-8587-3ff04032da64` acknowledged at 04:47:04 UTC; prior last-success record unchanged |
| Failure email delivery | Owner explicitly confirmed receipt at jimrharvey@gmail.com. This is recipient confirmation, not an inferred result from an HTTP response |
| Genuine recovery | Exit **0**, snapshot `4b18b207c80396fef6da94aba1e349a598a7e98e19ed70840ac3b996542017dd`; start and success acknowledged with run ID `2b676dbc-225b-40ed-9fac-1da3d6cffe96`; completion acknowledged 04:49:22 UTC after snapshot verification; data operation 20.032 s |
| Monitoring outage with successful backup | Actual curl failures forced through a process-local unreachable loopback proxy; no real URL/global network config changed. Backup still exited **0** and verified snapshot `6f41f3e3971c16f6494ac88bc3ae85d32ad536d4199ef9b2af006a2995487d47`; monitoring failures logged categorically in the new test unit/state |
| Simultaneous data/monitoring failure | Wrong-password fixture plus actual monitoring connection failures retained **Restic exit 12** and genuine last-success record. Both outage cases completed in 28.315 s combined |
| Isolated restore after enhancements | Snapshot `6f41f3…` retrieved from off-host storage; four captured file hashes, 1,000 rows and both indexes verified. Aggregate row checksum `2f065cb6e35689f056013bf9319cc069`; total restore 7.634 s. Only the newly generated disposable restored database was then cleaned up, after recording its checksum |
| Missed-run check arming | Owner created **Muzeum — Missed-run Test**, one-minute interval/one-minute grace, same email integration; URL entered through hidden helper. Genuine disposable backup exited **0**, snapshot `81055ebd16b7fa3dba2127bb27eaa701226b6b8bfb8ae4e1775c15728cb1be9d`; separate start/success signals acknowledged with run ID `4ce220b3-9803-4133-a728-00ac45cf2798` |
| Missed-run detection/email | Last temporary success 04:53:24.207618 UTC; no subsequent ping sent to that check. Its expected late threshold was 04:55:24.207618 UTC. Owner confirmed receipt of its DOWN email; confirmation recorded by 04:56:53 UTC. No explicit failure signal was sent to this temporary check, so the DOWN was the missed-run path |
| Temporary check cleanup | Owner confirmed deleting only the temporary hosted check. Server removed its secret URL entry and `/etc/harvj-backups/muzeum/missed-run-test.json`; verified the real `backup` URL was byte-for-byte unchanged in memory. Only `backup` remains configured; file remains 0600. Sanitized historical verification metadata is retained |
| Automated checks | Ten focused tests pass; Python compile and whitespace checks pass. General unittest discovery no longer executes the manual live-outage harness on import |

Start/success/failure records contain only phase, job name, acknowledgement status, timestamp and generated **run IDs**; run IDs are correlation metadata, not secret check UUIDs. Curl acknowledgements require exact OK. Connect/transfer/process deadlines remain two/five/seven seconds, with no retry loop. Monitoring failure never substitutes for a data job's original exit status. Actual start/success transport is proven by acknowledgements and the operation ordering; inbox access was not connected and successful recovery-email receipt was not independently claimed. Failure and missed-run email delivery were explicitly confirmed by the recipient.

Healthchecks management settings were not queried through an API or exposed account session. The real daily check's 24h/2h values are the owner's specified setup; missed-run notification behavior was exercised using the separate 1m/1m check and confirmed by the recipient. This does not claim a real 26-hour timeout was awaited or change the daily check's timing.

## Scope and operational changes

All live backups used only the existing disposable readiness database/files. They used manual **bootstrap** Storage Box access, explicitly opted in for tests; no unattended main-account job was enabled. The Muzeum subaccount key-installation confirmation and directory-isolation test remain outstanding. No attempt to log in to the gated subaccount was made.

The earlier enhanced proof failure was a transient test-harness issue: the failed proof omitted writable private temp storage under ProtectSystem=strict. The successful live unit included PrivateTmp=yes, like the installed service template. Snapshot metadata readback succeeded and the enhanced data path now passed. The disposable restore cleanup-order fix also passed live verification. Earlier failures remain in the journal; they were not relabeled successes.

Only the new backup helper/monitoring/test tooling was updated. Positive acknowledgements now flush immediately to the journal without URLs. The separately opted-in notification-test profile never changed the real daily check or its schedule. No backup snapshot, existing archive, other application's job/service/credential/database, DNS, or Muzeum deployment was altered. Only the intentional failed test unit's failed state was reset after evidence collection. Existing Arkham, Caddy, PostgreSQL and Continuum dashboard services remained active.

The temporary-test URL and profile have been removed, not merely disabled. No Healthchecks account API key is present on the server. Manual outage proxy variables existed only in the test process; no system/user proxy configuration changed. The real check was left at its genuine 04:49:22 UTC verified-completion signal; the separate missed-run test never refreshed it.

## Production timer readiness

**Not ready to enable a production backup timer.** Monitoring transport, failure-email delivery, isolated missed-run detection and exit-status behavior are verified, but:

1. Muzeum is not deployed and has no production databases/files to protect. The installed helper deliberately accepts only disposable readiness capture; production capture requires a reviewed consistent four-database/files/secrets procedure.
2. Restricted Muzeum subaccount key installation, SFTP authentication and base-directory isolation have not yet been confirmed/verified; bootstrap access must not become the unattended credential.
3. The production profile `/etc/harvj-backups/muzeum/config.json` has not been activated. Independent verification/restoration Healthchecks URLs remain separate future checks; they must not reuse the daily-backup URL.
4. Independent escrow of the Restic recovery password/key material and final production capture/restore procedures remain deployment prerequisites.

All four new timers (`muzeum-backup`, `-check`, `-restore`, `-monitor`) remain **disabled**. No existing application backup was interrupted, no code pushed and Muzeum was not deployed. Production or readiness-timer activation still needs its explicit approval and the relevant gates above.

Ten daily Storage Box snapshots remain user-confirmed additional protection, controlled outside the dedicated server. They are not the sole recovery mechanism and cannot substitute for independent Restic restores.
