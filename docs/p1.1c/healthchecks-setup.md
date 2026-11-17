# Healthchecks.io — secure Muzeum integration

The real ping URL is now provisioned and live verification is recorded in [the current results](healthchecks-live-verification.md). The instructions below remain the secure setup/retest runbook; preparation-era pending statements are historical. No API credential is needed on the server; no SMTP relay is used.

## Account settings to create

| Setting | Value |
| --- | --- |
| Project | harvj-backups |
| Check | Muzeum — Daily Backup |
| Schedule type | Simple interval |
| Period | 24 hours / 86400 seconds |
| Grace | 2 hours / 7200 seconds |
| Email notification | jimrharvey@gmail.com, verified and enabled for this check |
| State | Active, not paused; no filtering that ignores legitimate POST pings |
| Description | Initially covers disposable backup-readiness data only; production coverage requires separate activation |

The [Healthchecks schedule documentation](https://healthchecks.io/docs/configuring_checks/) explains that grace applies both to late/missed pings and the duration between start and completion. The [notifications page](https://healthchecks.io/docs/configuring_notifications/) explains that notification integrations must be enabled for the individual check. Creating the project/account alone does not prove email delivery or arm a never-started check.

## Secure ping-URL entry

From your own terminal, run:

```sh
ssh -t harvj 'sudo -n /usr/local/lib/harvj-backups/configure-healthchecks backup'
```

Paste the check's **base HTTPS UUID ping URL** at the hidden prompt. Do not put it in the SSH command, shell history, chat, Git, unit files or an environment variable. The helper:

- Requires root and a TTY and validates the HTTPS hc-ping.com UUID format.
- Refuses unsafe existing configuration or directories.
- Writes atomically to `/etc/harvj-backups/muzeum/monitoring.json`, root:root **0600**, under **0700** root-owned directories.
- Preserves other check entries, prints only the job/path/permissions, and sends **no ping** during entry.
- Stores only per-check URLs, never an account/project management API key.

Tell the agent when entry is complete, without sharing the URL. Do not use cat, echo, shell tracing or a config dump to verify it. Check only owner/mode and whether the required `backup` entry exists. The executable source is `ops/backups/configure_healthchecks.py`; its server path uses a hyphenated executable name.

## Signal and exit-status behavior

`monitoring.py` is installed under `/usr/local/lib/harvj-backups/`. The backup hook sends POST start, success and failure signals using a shared random run UUID. A successful backup must complete Restic, pin/check the expected repository identity, read back the new snapshot and validate its hostname/path/tags, and publish the genuine last-success record **before** entering the success signal path. Failed repository/snapshot verification never sends success. Initial URL provisioning itself does not send success or start the check's clock.

The [Healthchecks ping API](https://healthchecks.io/docs/http_api/) defines the start and failure suffixes and acknowledgements. The implementation requires HTTP success plus the exact `OK` body; an HTTP 200 `OK (not found)` or rate-limited response is not treated as acknowledged.

A monitoring outage does **not** change a successful backup's zero exit code, replace a nonzero backup result, or hide the original backup exception. Native Restic failure codes are retained by the helper. Monitoring acknowledgement/failure is recorded separately in root-protected `state/last-monitoring-backup.json` and the scoped journal. This supersedes the previous experimental behavior that made a monitoring outage fail an otherwise successful data job. Systemd OnFailure handles actual backup failures, including failures outside normal completion handling; it must not be triggered solely by a missing success acknowledgement.

Network limits: two-second connect timeout, five-second curl transfer deadline and seven-second Python process deadline; no retry loop. TLS verification remains enabled, the URL is passed through curl stdin rather than argv/environment, and errors are logged by category without URL or response-body disclosure. Monitoring-state/logging faults are also isolated from the data job's result. The real URL is used only from protected server configuration; it is not exposed in logs, argv, environment or Git.

The server's existing freshness monitor treats a genuine last-success record older than **26 hours** as stale, matching 24h + 2h; it never sends success merely because the monitor ran. Healthchecks independently detects missed runs if the host, timer or local monitoring process stops. This external behavior must be verified in Console after the first genuine start/completion pings.

Separate `verification` and `restoration` URL slots and hooks are prepared. Do not reuse the daily-backup URL for weekly integrity or restore checks: their pings could mask a missed daily backup. Add those checks/URLs separately before enabling their corresponding weekly timers. Other applications have disabled adoption examples with separate checks; their jobs/configurations have not been changed.

## Acceptance after provisioning

These steps describe the acceptance procedure. The actual completed live tests and remaining gates are in [the results](healthchecks-live-verification.md). Muzeum subaccount key installation and isolation verification are also still awaiting the user's confirmation; do not bypass that gate with the bootstrap identity for unattended backups.

1. Verify root-only URL storage without displaying it. Verify in Console the project, exact 24h/2h schedule, active state and enabled/verified email integration for this check. Keep account credentials off the server.
2. Run a genuine disposable readiness backup with restricted application credentials. Check that Healthchecks records start and then success only after repository and snapshot verification. Record snapshot ID, exit status, and acknowledgement separately. Check's next-due/grace information must now be visible; no artificial success ping to arm it.
3. Run the isolated wrong-password fixture configuration, leaving the real Restic password untouched. Expect the native backup failure status (e.g. Restic 12), a failure signal, a Down state and a delivered alert to jimrharvey@gmail.com. The last genuine successful snapshot record must remain unchanged.
4. Run another valid, verified readiness backup; verify recovery/Up in Healthchecks and recovery notification according to its enabled email integration. A 200/OK ping alone is not proof that email arrived; confirm delivery in the account/inbox.
5. Verify missed-run alerting: before production protection is active, a controlled **disposable-readiness** check can be left without pings for its real 24h + 2h window. Confirm Down and delivered missed-run email. Resume a genuine verified backup afterward. Do not disable existing application backups or a future production-protection job to perform this test. A separate temporary notification-test check with a shorter period is an alternative; never shorten/change the real daily check silently or reuse another application's URL.
6. Simulate monitoring unavailability using a separate local test fixture, not by replacing the real URL. Confirm bounded execution, sanitized warnings and preservation of both successful and failing backup exit statuses. The local and installed isolated checks already exercise this behavior; actual service/inbox tests remain pending.

A real 26-hour missed-run test cannot be completed during URL-entry preparation. Record its start/deadline and final delivery evidence when run; do not claim that the test passed based only on intended settings. Account settings can be checked through Console without persistent API credentials.

## Verification and operational boundary

**Ten focused automated tests pass**: signal ordering, failed snapshot verification, exact acknowledgement handling, URL privacy, timeout behavior, successful and nonzero exit preservation (including Restic 12), and secure URL validation. Python compilation passes; the installed server wrapper was also tested with monitoring mocked unavailable and preserved success and exit 12. [Test output](verification/healthchecks-tests.txt).

Read-only access to the existing bootstrap repository confirmed snapshot `7d42065a771b13593fa12967343656debdd1b6d7df06aacd4d8447b677889598` can be read back and carries hostname `harvj-muzeum` and expected readiness tags. This verifies the metadata-readback interface, not a new fully successful enhanced backup run. The earlier final transient proof still needs revalidation under the full unit sandbox (including PrivateTmp); it did not create a new snapshot or overwrite last-success. No new backup or subaccount connection was started in this Healthchecks-preparation step.

Only isolated backup scripts were updated and the hidden URL provisioner was installed. No Healthchecks account/check was created, API key stored, SMTP installed, notification sent, timer enabled, existing app backup modified, code pushed or Muzeum deployed. All new backup timers remain disabled. Live success/failure email tests, missed-run configuration verification and final readiness scheduling await secure URL entry and the subaccount-key confirmation.
