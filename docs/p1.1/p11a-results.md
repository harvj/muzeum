# P1.1a results and remaining blockers

Executed locally 2026-11-15, Ruby 3.3.5, Bundler 4.0.3, Rails 8.1.2, PostgreSQL 16.15. No full historical import, canonical resolution, push, deployment, DNS/Caddy/service modification or production database operation. Infrastructure discovery used metadata-only read-only SSH/SQL and unauthenticated health probes; see [inventory](infrastructure-inventory.md). Existing roadmap edits from the preceding documentation task are included in the review commit.

## Validation

| Check | Result |
| --- | --- |
| Disposable database | New local cluster `/tmp/muzeum-p11a-postgres`, loopback port 56488, database `muzeum_p11a_test`; production/development databases unused |
| Migration and suite | Authentication migration applied; **60 examples, 0 failures**, including existing 49 and 11 new request/model/system examples; final full run also passed with BROWSER_TESTS=1 (real browser) |
| Actual browser | **1 system example, 0 failures** with BROWSER_TESTS=1 and headless installed Brave/Chromium through Selenium; covers login/logout/protected root with Turbo loaded |
| Legacy transition rehearsal | Separate `muzeum_p11a_transition` loaded from original committed schema; legacy User ID 123/source name and JSON observation payload retained after migration, still inactive for login |
| Zeitwerk | Eager loading passes |
| Production assets | Propshaft compilation passes with SECRET_KEY_BASE_DUMMY=1, no provider credentials; import map, Turbo and Stimulus assets produced |
| RuboCop | 87 files, zero offenses |
| Brakeman | Zero errors/warnings with strict exit flags |
| Capistrano | Production task graph loads locally; missing approval inputs abort before network operations. No remote deployment/check/migration task invoked |
| Dependency audit | **Fails**, 237 findings across 22 gems; 1 Critical, 27 High, 61 Medium, 24 Low, 124 Unknown. [Full unfiltered output](dependency-audit.txt). No dependency upgrades or exceptions |
| GitHub Actions | Configured independent test/browser and quality matrix jobs on PR/every main push; not run remotely because no push is authorized. No deployment job/secrets |

The browser test also runs via Capybara RackTest without BROWSER_TESTS=1; that fallback does not verify JavaScript. Rate limiting uses Rails' built-in controller limiter with shared Solid Cache in production; distributed limiter behavior has not been production-tested. Service/proxy templates, backup restoration, real SSH deployment, runtime-role grants and actual rollback have not been exercised on Hetzner and are not claimed verified. No systemd template can be fully integration-tested on macOS.

The authentication migration preserves existing rows, relaxes provider username requirement and adds nullable credential/activation columns plus database-constrained unique normalized emails and sessions. No account associations or provider ownership are inferred. Expired sessions are rejected; password changes/disabling revoke sessions. Default Cable and Active Storage routes remain disabled pending scoped authorization. Missing/forged session cookies and unauthenticated Frame requests fail access checks. CSRF protection is explicitly tested enabled. No browser endpoint accepts another user's ID or exposes archive/import/resolution data.

## Audit triage and production blockers

No finding is accepted, suppressed or automatically upgraded. Severity is scanner-reported, not a verified exploitability judgment. Treat the critical/high and unknown-severity findings as unresolved blockers until individually reviewed; applicable critical/high findings must be remediated before exposure. The scan uses a refreshed advisory database and records its revision in the full output. The pre-existing lock versions were retained while requested new dependencies were added.

- actionpack/actionview/activesupport, Rack/rack-session, ERB, HTML sanitizers (rails-html-sanitizer, loofah, crass): request/session/rendering paths are relevant to the new login surface. Do not waive these based on a clean Brakeman scan.
- Puma and websocket-driver: HTTP/proxy and possible Cable paths require version/advisory review before internet exposure; no external Cable subscriptions were introduced.
- Nokogiri, JSON, msgpack, addressable, concurrent-ruby: review actual parser/deserializer/URI/concurrency usage, including Last.fm/XML work deferred to P1.2. Deferral does not silently exempt installed dependencies.
- actionmailbox, activestorage, action_text-trix, mail, net-imap: inspect loaded/unused framework functionality, routes and inbound/mail/file processing assumptions before classifying individual advisories nonapplicable. No mail-based recovery or uploads were introduced.
- net-ssh: relevant to Capistrano deployment tooling even though it is not a browser request path. Host-key checking and no agent forwarding do not automatically mitigate every advisory.

The next security review must record per-advisory ID/version, severity, reachable path or evidence of nonapplicability, proposed version change/mitigation, owner, regression checks and explicit risk acceptance/expiry for any narrow exception. No waiver exists today. Remediation is a reviewed follow-up rather than an unattended bundle update.

Other unresolved gates: dedicated Muzeum user/home/runtime and repository key, explicit role/schema grants and connection budgets, off-host backup/restore proof and owner, DNS A/AAAA/TLS issuance, initial operator account, alert recipient/thresholds, approval-record format and final resource acceptance. The [runbook](deployment-runbook.md#exact-proposed-server-changes-all-pending-explicit-approval) lists every proposed server mutation. None has been performed.
