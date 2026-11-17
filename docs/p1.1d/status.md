# P1.1d — production deployment and acceptance

Muzeum is live at **https://muzeum.fm/**. The application, authentication, association, historical importer and dashboard are usable. The first historical backfill is still running. The [numbered roadmap](../roadmap.md) is canonical; the [operations runbook](operations.md) covers deployment, backups and recovery.

| Item | Verified result |
| --- | --- |
| Application SHA | `b2dc302078b86cd4960e130e96908d64a2feb25a` |
| Application CI | [All checks passed](https://github.com/harvj/muzeum/actions/runs/44016557191) |
| Recovery operations source | `3fee4f13bf91af24d6f12ed61c1f94c9b6b9d688`; [CI passed](https://github.com/harvj/muzeum/actions/runs/44020808102) |
| Runtime | Rails 8.1.4.1 / Ruby 3.4.12; independent Muzeum web and Solid Queue services, restricted database roles and bundle directory |
| HTTPS / authorization | `/up` 200; signed-out `/` 302 to sign-in; protected mutations/Frames tested; callback query logging disabled |
| Existing applications | Auth, CE, harvj.com and Arkham public health checks 200; their application code, services, schedules and databases were not changed |
| Import checkpoint, 2026-11-17 05:05:09 UTC | `qalephd`: **155,000 / 292,852 observations**, 775 raw pages, next page 776/1465, running, no error |
| Canonical recordings | **0**; no MusicBrainz resolution or surface attachment performed |
| Boot persistence | Muzeum web/worker enabled and active |
| Backup activation | Four production timers enabled/active at `2026-11-17T05:01:06Z`, after independent escrow and actual sandboxed recovery gates passed |

## Authentication and account association

The existing `auth.harvj.com` account and enrollment were reused. No new Auth account, password or MFA enrollment was created. Muzeum stores a local `(issuer, subject)` profile, not an email-based identity or independent credentials. Existing source-only profiles remain unlinked until explicit operator reconciliation.

The established `openid_connect` Ruby client handles confidential code/S256 exchange and signed ID-token validation. Server-side one-use state, nonce and verifier are browser-bound and expire. Signature/JWKS/RS256, issuer, audience/azp, nonce and expiry are checked. Native offline-access consent establishes an encrypted, revocable grant. Sessions enforce 12 hours idle/seven days absolute; native introspection checks admission every 60 seconds and fails closed during provider outages. Opaque refresh introspection returns `client_id` without `sub`; identity remains bound to the verified exchange, and any conflicting returned subject is rejected. A real grant remained active 1,707 seconds after login, beyond ID-token expiry.

Production browser SSO/consent, account association and import initiation succeeded. The operator confirmed refresh/session continuity, local logout and fresh SSO re-login. Web and worker restarts and coordinated backup pauses preserved durable state. CSRF/origin checks remain enabled; positive browser/form submission and rejection tests pass. Forms use `strict-origin-when-cross-origin`; only callback responses use `no-referrer`. Authorization redirects and sensitive query/parameter values are filtered from logging.

Last.fm's existing Muzeus application key was privately recovered, validated and provisioned. No Last.fm user credentials were requested. `user.getinfo` validated `qalephd`; the association is explicitly **ownership unverified**. Transient client-registration secret material was removed after comparison with the protected installed configuration; provisioning reuses existing credentials rather than rotating or duplicating the client.

## Import and dashboard

The worker processes bounded 200-observation pages with a fixed upper time bound, per-user serialization, unique exact-name/time fingerprints, five-attempt bounded network/rate-limit retries and explicit resume/restart. Raw XML/checksum/page lineage, observations and progress commit atomically. PostgreSQL triggers reject bulk source/raw-page mutation or deletion; `db/structure.sql` is the schema bootstrap. Different same-second observations are retained; exact repeats are deduplicated. No raw XML is invented for legacy parsed-only records.

The Rails/Hotwire dashboard reads scoped persisted totals, distinct exact observed names, UTC range and durable progress/error/update state. Album and track counts include the reported artist; empty albums are omitted. Counts are observations, never canonical MusicBrainz entities. A delayed real queue probe completed after worker restart and code deployment. The historical import continued across writer quiescence and resumption with matching checkpoint/insert counts and no errors.

[Environment assets, prompt, desktop/mobile previews and recordings](environment.md). Both modes use identical geometry/typography, stationary stone and a separate occasional illumination layer, with pause/reduced-motion/static fallbacks. [Shared session dropdown and compatible CE/Auth adoption](shared-session-dropdown.md). Administrator navigation remains withheld because the current Auth consumer contract supplies no administrator-role evidence; email, application membership and subject are not treated as admin proof.

## Recovery and backup gates

The restricted Muzeum Storage Box subaccount/repository, key isolation and disposable recovery were established in P1.1c. The operator independently retrieved the 1Password recovery document and verified it at `2026-11-17T03:33:20Z`; SHA256 `a96a652eaa641084e0bac3e9fba21f4a1758d43e9160e8aa53838022fbfdae5f`. Restic/SSH credentials remain independent of application/provider credentials. Secret values were not displayed or committed.

| Evidence | Result |
| --- | --- |
| Pre-migration snapshot | `24578e19b68d073813a2cba7c0603c336f868a8dd3cca202ee4553ccb76f6ff4`; four isolated databases restored before migrations |
| Migrated-schema snapshot | `4365dcd2eb3b7ec66c79d28b97600a189edaecd6ecf9df7a3a8c60e5d0fe71a7`; four databases/11 files, matching fingerprints |
| Actual identity/history/session restore | `b4eb6682f7cbb76f50ff6261e0a85cfd09e7ca4c51a91d300d668d94c01dfaf9`; **13,000 scrobbles, 65 raw pages, one linked profile, one encrypted session** |
| Strict systemd restoration | Four database/file fingerprints matched; exact application booted read-only against all four isolated targets and decrypted the session; **40.914 seconds**; disposable databases/files removed |
| Native sandboxed backup | `4cfbbfae55af14fc4b0f6dcc686fd8bf028dbc9781978dd76ab0553bff7a9157`; **42.070 seconds** |
| Native full encrypted-data integrity | **45.682 seconds**, success/exit 0 |
| Native freshness monitoring | Success/exit 0; production-mode freshness checked |
| Signaling | Genuine Healthchecks start/success acknowledgments for backup, integrity and restoration; earlier delivered failure/missed-run evidence retained in P1.1c |
| First-deployment rollback | Only Muzeum route/services withdrawn; original shared Caddy bytes verified; data/revision retained; same release reactivated and HTTPS verified |

All four installed backup services passed under their actual resource/filesystem sandbox before activation. The shared host backup lock prevented concurrent operations; a refused restore was retried without interrupting another job. Runtime schema CREATE is false on all four Muzeum databases; migrations use a separate OS/database identity. The read-only Ruby interpreter is reused without modifying Auth files/gems; Muzeum's bundle, configuration, services, roles and data are separate.

Enabled schedules: nightly backup **02:00 UTC**, Sunday integrity **04:00 UTC**, Sunday isolated restoration **06:00 UTC** (each up to 15 minutes randomized delay), and hourly freshness checks. Capture pauses/resumes only previously running Muzeum writers/workers. Retention planning is 30 daily/12 weekly/12 monthly; **destructive pruning remains disabled**. Detailed live activation receipts remain root-only under `/var/lib/harvj-backups/muzeum/state`.

## Verification and limits

**82 RSpec examples** pass with Chrome, including real signed token manipulation/claims, state expiry/binding/replay, session deadlines/revocation/outages, positive CSRF submission, protected routes, association, statistics, import replay/interruption/atomicity/source immutability, bounded retries, queue consumption and responsive modes. **28 backup/recovery helper tests** pass. RuboCop has no offenses; Brakeman has no warnings; updated dependency auditing has no vulnerabilities. Zeitwerk, production asset compilation, SQL bootstrap and full migration replay passed. [Retained verification logs](verification/rspec-browser.txt).

The initial backfill is ongoing; no completed full-history or 250k benchmark claim is made. Same-total upstream history edits and indistinguishable identical same-second deliveries cannot be resolved reliably by Last.fm; changed totals fail safely and can be restarted. Sharing/renames require operator reconciliation until P1.2's account model. Advanced browsing, interpretation/aggregation and MusicBrainz resolution remain deferred. CE/Auth dropdown adoption and provider-authenticated administrator-navigation evidence require separate authorization. Native libvips is absent; image-variant routes are disabled and environmental assets are already rendered.
