# Healthchecks management credential provisioning

The project management key is now provisioned and its ownership/mode verified as root:root 0600. The installed provisioning command below is retained for reference; it refuses to overwrite the existing key. Use a private interactive terminal without terminal recording/session transcription for future provisioning:

```sh
ssh -t harvj 'sudo -n /usr/local/lib/harvj-backups/configure-healthchecks-api'
```

Paste the `harvj-backups` project **read-write** management key at both hidden prompts. Do not put the key in the command, environment, chat or Git. The helper refuses echoed-input fallback and existing credential paths, disables core dumps, validates a single-line credential, and atomically stores it at `/etc/harvj-backups/healthchecks-api-key`, root:root 0600, inside the existing root-only 0700 directory. It prints only confirmation, never the value. It does not contact Healthchecks or alter checks/timers. Host terminal auditing must not record secret input.

The user's explicit management-key authorization supersedes the earlier per-check-only credential preference for this provisioning task. Scheduled backup jobs continue to need only their per-check ping URLs; they must not read/use the management key. Revoke/remove the project management key after management work if ongoing automated reconciliation is not desired; do not remove the ping configuration.

## Follow-up after secure entry

Use the [official Management API v3](https://healthchecks.io/docs/api/) with bounded HTTPS requests, no redirects, no raw response/error logging, and credentials passed in memory/stdin rather than arguments. Discover checks and notification integrations. Match the existing daily check using its securely stored ping URL to confirm the expected project, and identify its existing email integration. Listing integrations exposes kind/name/ID, not necessarily the recipient address or delivery proof: retain the earlier recipient-confirmed delivery evidence.

Create only missing Muzeum checks, reusing that email integration:

* `Muzeum — Integrity Verification`: weekly Sunday 04:00 UTC, matching the disabled integrity timer; proposed two-hour grace includes its 15-minute jitter.
* `Muzeum — Restoration Verification`: weekly Sunday 06:00 UTC, matching the disabled restoration timer; proposed two-hour grace includes its 15-minute jitter.

Preserve every existing check and its schedule. Discover before creating; stop on duplicate/ambiguous matches or incompatible existing configuration instead of updating it. Avoid an upsert that could silently alter an existing check. Capture returned per-check ping URLs directly into root-only `monitoring.json`, preserving the daily URL, without printing responses. Read back schedules and integrations after creation. New checks must not receive synthetic success signals; completion signals require real verified operations. Keep checks unarmed until genuine verification; document that scheduled missed-run coverage requires separately approved timer activation.

## Completed management verification

The read-write project key authenticated successfully. Discovery found the existing `Muzeum - Daily Backup` check (24-hour interval, two-hour grace) and one email integration already attached to it. Matching its stored ping URL confirmed project context without printing any ping URL or API key. The API does not independently prove the project display name or email recipient; earlier recipient-confirmed email tests remain the delivery evidence.

Installed `/usr/local/lib/harvj-backups/manage-healthchecks` and created the two missing checks with the existing email integration:

| Job | Check | Schedule | Grace |
| --- | --- | --- | --- |
| verification | Muzeum — Integrity Verification | Sunday 04:00 UTC (`0 4 * * 0`) | 2 hours |
| restoration | Muzeum — Restoration Verification | Sunday 06:00 UTC (`0 6 * * 0`) | 2 hours |

The returned ping URLs were wired to `verification` and `restoration` in `/etc/harvj-backups/muzeum/monitoring.json`, root:root 0600. The daily mapping was preserved. Before/after comparison confirmed existing check settings were unchanged. A second live reconciliation created no checks and preserved mappings. The helper supports only discovery GETs and new-check POSTs; no update/delete/pause/resume endpoints or upserts are available. Requests use stdin-only credentials, TLS verification, no redirects, three-second connect/ten-second transfer/twelve-second process limits, and no automatic retries. Raw responses/errors are never printed.

No pings were sent: the new checks are unarmed until genuine verified jobs run. Their schedules are prepared, but unattended missed-run protection is not active while checks remain new and all four systemd timers remain disabled. No new live delivery test is claimed here. Scheduled jobs continue using only per-check URLs, not the management key.

Seventeen local tests passed, covering credential protection, reconciliation idempotence, preservation of existing schedules and bounded request transport. No real credential was used in local tests. Sanitized server evidence is at `/var/lib/harvj-backups/muzeum/state/healthchecks-management-verification.json`.

Operational changes were additive helper installation, two hosted checks and the two root-only ping mappings. No production timer activation, application deployment/push, production database change or existing application backup modification occurred.
