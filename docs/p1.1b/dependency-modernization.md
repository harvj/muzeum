# P1.1b — Dependency modernization

Completed locally 2026-11-15 against P1.1a commit `96024b9`. No server connection/change, production database operation, historical import, canonical resolution, push or deployment. Disposable PostgreSQL databases only. See the [complete version inventory](dependency-inventory.md), [advisory reconciliation](advisory-reconciliation.md) and [final audit](dependency-audit.txt).

## Result and version decisions

**The dependency audit moves from 237 raw matches to zero**, with no ignored advisories. Updated 88 existing gem/toolchain names including Bundler; removed nine unused/transitively superseded packages and added three, with native platform records collapsed. Every selected version was installed locally. The lockfile retains checksums and supported Linux platform records for later host installation; Linux CI has not run because nothing was pushed.

| Component | Before | After | Reason/compatibility |
| --- | --- | --- | --- |
| Ruby | 3.3.5 | 3.4.12 | Current patched 3.4 maintenance line, tested locally |
| RubyGems / Bundler | 3.6.9 on new Ruby / 4.0.3 | 4.1.0 / 4.1.0 | Current stable toolchain; matched versions avoid vendor URI warnings seen with new Bundler and stock RubyGems |
| Rails and all framework components | 8.1.2 | 8.1.4.1 | Security release, remain on Rails 8.1/defaults 8.1 |
| Puma | 7.2.0 | 8.1.1 | Current stable security/maintenance line; existing explicit loopback bind and configured threads retained |
| HTTP.rb | 5.3.1 | 6.0.4 | Current stable; change timeout hashes to keyword arguments in both clients |
| PostgreSQL gem | 1.6.3 | 1.7.0 | Compatible update, PostgreSQL 16.15 tests |
| Solid Queue | 1.3.1 | 1.7.2 | Additive batch schema migration; durable job lifecycle verified |
| Solid Cable | 3.0.12 | 4.1.0 | Async batched broadcast writer; database broadcast/graceful flush verified; external Cable route remains disabled |
| image_processing | 1.14.0 | 2.2.0 | Security hardening; explicitly retain optional ruby-vips backend lazily |
| Net::SSH | 7.3.0 | 8.1.2 | Security fixes; updated SCP/SFTP/SSHKit, strict host verification retained, encrypted synthetic key tested |
| RSpec Rails | 8.0.2 | 8.1.0 | Current compatible release; request/model/browser coverage preserved |
| RuboCop / Brakeman | 1.82.1 / 8.0.1 | 1.92.2 / 8.1.0 | Current analysis tools, no application-style rewrite needed |
| Nokogiri / Rack / rack-session | 1.19.0 / 3.2.4 / 2.1.1 | 1.19.7 / 3.2.8 / 2.1.2 | Patched versions across all locked platforms |

The full inventory lists every direct and transitive dependency, installed/locked-before values, current compatible/latest stable releases and final selection. No compatible updates remain. Unconstrained `bundle outdated` still lists **diff-lcs 2.0.0** and **Marcel 2.1.0**: current RSpec requires `diff-lcs >=1.2,<2`, and Active Storage 8.1.4.1 requires `marcel ~>1.0`. Keep 1.6.2 and 1.2.1 respectively rather than overriding upstream compatibility. They have no audit findings. No prerelease dependency, Rails main branch, patched fork or advisory waiver is introduced.

Removed the unused Dockerfile, Docker entrypoint/ignore file, Kamal configuration/hooks/secrets scaffold and Kamal/Thruster binstubs/dependencies following the Capistrano deployment decision. GitHub Actions' PostgreSQL service container remains; it does not need an application Dockerfile. Capistrano 3.20.1 and its release/shared/rollback model remain. bcrypt_pbkdf is now explicitly a development dependency to retain encrypted SSH-key support after removing Kamal; Net::SSH 8 uses OpenSSL for Ed25519 and no longer needs the old ed25519 gem. OpenSSL gem 4.0.2 is locked through Net::SSH; local linked library reports OpenSSL 4.1.0.

## Ruby recommendation

Adopt **Ruby 3.4.12**, with `.ruby-version`, Gemfile/lock and proposed Capistrano/systemd environments aligned. The [Ruby branch policy](https://www.ruby-lang.org/en/downloads/branches/) lists 3.3 as security-only and 3.4 as normal maintenance. [Ruby 3.4.12](https://www.ruby-lang.org/en/news/2026/10/23/ruby-3-4-12-released/) includes October regexp-engine fixes. Retaining 3.3.5 would retain an old interpreter; even retaining the 3.3 line would require a patched 3.3 release.

[Ruby 4.0.9 is also stable](https://www.ruby-lang.org/en/downloads/releases/). A 4.0 move is not needed to obtain a maintained, patched runtime or resolve this bundle's findings. Prefer the smaller 3.4 compatibility step for the first production deployment; Ruby 4 would require its own default-gem/native-extension/runtime compatibility exercise. Do not interpret its deferral as a claim that 4.0 is unsupported. The verified server has only Ruby 3.4.8 under the existing deploy user: provision 3.4.12 plus RubyGems/Bundler 4.1.0 under the independent Muzeum identity only after approval, without modifying that existing runtime.

Local ruby-build definitions were older than the desired release. Installed 3.4.12 with a task-local definition pointing at the official tarball and verified official SHA-256 `5e5d85ad93b0adcccbad47733680f4892bd0078e3342437f7babce01c1872479`; no system-wide build-definition edits. Existing Ruby installations were retained.

Primary compatibility references: [Rails 8.1.4.1 security release](https://rubyonrails.org/2026/11/4/Rails-8.0.5.2-and-8.1.4.1-have-been-released), [HTTP.rb 6 upgrade guide](https://github.com/httprb/http/blob/main/UPGRADING.md), [Puma release history](https://github.com/puma/puma/blob/main/History.md), [image_processing changes](https://github.com/janko/image_processing/blob/master/CHANGELOG.md), [Net::SSH changes](https://github.com/net-ssh/net-ssh/blob/master/CHANGES.txt). Installed gem source/templates were also inspected for queue schema, Cable batching and key support.

## Database and application compatibility

Authentication, user/source identity separation, CSRF, revocable sessions, ERB/Hotwire/import maps/Propshaft, server-side rules and explicitly approved Capistrano deployment remain intact. No OAuth, frontend API or new archive/resolver functionality. The only client adjustment is HTTP.rb 6's keyword timeout API; existing provider mocks pass without live traffic.

Solid Queue 1.7 adds `solid_queue_jobs.batch_id`, its index, and batch/batch-execution tables. Updated `db/queue_schema.rb` for empty-database bootstrap and added **`db/queue_migrate/20261116020000_add_solid_queue_batches.rb`** for existing queues. An old-schema queue containing a sentinel job was upgraded and the job retained. The migration deliberately refuses down rollback that could discard batch/job state; code rollback must preserve schema and review queued job compatibility. No production database has been migrated. New auxiliary databases still need the documented schema bootstrap; do not run the new batch-only migration against an otherwise empty queue or load a snapshot over existing jobs. Solid Cable's old extra channel index is harmless and retained; no destructive cleanup is needed.

Schema-loaded and migration-replayed primary databases have equivalent columns/types/nullability/defaults, indexes and foreign keys. Rails' newer dumper preserves physical column order differently from the existing snapshot, so comparison ignored column ordering rather than rewriting the primary schema. No source-data schema or payload changed.

CI keeps every-main-push/PR tests and separate quality jobs with no deploy trigger or production credentials. Added migration replay in a separate disposable CI database, eager loading, production asset build and local-only Capistrano task validation. `bin/ci` now enables browser tests explicitly and refreshes its advisory database. CI uses the Ruby/locked Bundler versions; remote CI execution remains pending a separately authorized push.

## Verification results

PostgreSQL 16.15, task-created cluster `/tmp/muzeum-p11b-postgres`, loopback port **56489**. Databases `muzeum_p11b_schema` and `_migrate`, four production-mode **local disposable** databases (`_primary`, `_cache`, `_queue`, `_cable`) and `_old_queue`. No development or production database was used. The cluster was stopped after verification.

| Check | Result / evidence |
| --- | --- |
| RSpec + actual Capybara browser, schema bootstrap | **60 examples, zero failures**, headless Brave/Chromium with Turbo loaded; [output](verification/rspec-schema.txt) |
| RSpec + actual browser, migration replay | **60 examples, zero failures**; [output](verification/rspec-migrated.txt) |
| Fresh primary schema bootstrap / all migrations | Pass; [migration transcript](verification/migrations.txt); normalized structures agree |
| Fresh four-database production-mode bootstrap | Pass via explicit localhost-only URLs and `db:prepare`; old queue transition passes with existing job retained, [output](verification/queue-transition.txt) |
| Queue/Cache/Cable smoke | Durable enqueue/claim/perform/finalization, cache write/read and batched Cable database broadcast/flush pass; [output](verification/adapters.txt) |
| RuboCop | **88 files, zero offenses**, [output](verification/rubocop.txt) |
| Brakeman 8.1.0, strict flags | **Zero errors/warnings**, [output](verification/brakeman.txt) |
| Vulnerability audit, refreshed DB | **Zero findings**, [output](dependency-audit.txt); advisory DB `98dc44b74a91b82b95af415685b0a223a750c049` |
| Zeitwerk | Pass, [output](verification/zeitwerk.txt) |
| Production assets | Pass, [output](verification/assets.txt); visible optional native libvips warning described below |
| Puma configuration | Puma 8 loads the application config and retains explicit loopback binding; [output](verification/puma-config.txt) |
| Capistrano | Task graph loads, [output](verification/capistrano-tasks.txt); absent approval aborts before any remote action, [output](verification/approval-guard.txt) |
| SSH crypto compatibility | Net::SSH 8 locally loads a newly generated encrypted Ed25519 test key with bcrypt_pbkdf; no server connection or real private-key access |
| Bundle / whitespace | `bundle check` and `git diff --check` pass; no final compatible updates |

Reproduction uses `RAILS_ENV=test DATABASE_URL=postgresql://<local-role>@127.0.0.1:56489/<disposable-db>` with `rails db:schema:load` for one new database and `SCHEMA=/tmp/muzeum-migrated-schema.rb rails db:migrate` for the other. Run `BROWSER_TESTS=1 CHROME_BINARY=<installed-Chromium-binary> bundle exec rspec` against each. Then run strict Brakeman, RuboCop, refreshed bundler-audit, Zeitwerk, `RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 rails assets:precompile`, and `bundle exec cap production -T`. Substitute only disposable local targets. A browser binary/driver and native build prerequisites are required. Do not run the general setup script against an existing developer database for this rehearsal.

## Security reconciliation and remaining production gates

The original 237 entries comprise **132 distinct gem/advisory pairs**. Fifteen Nokogiri advisories were each repeated across eight native-platform lock records, accounting for 105 duplicate entries. The old affected versions really matched the advisory ranges; duplicate reporting and presently unused routes do not make them safe versions. Re-auditing the original lock with the final advisory DB still yields 237 entries; updating the lock resolves all. CVE/GHSA aliases are not counted as separate vulnerabilities. The [reconciliation table](advisory-reconciliation.md) records every distinct old finding, severity, repetition count and final version.

**Remaining reported dependency advisories: none**, so no remaining advisory severity/exploitability/remediation entry or exception is needed. This result covers the lockfile and scanner database, not all possible application defects, native OS libraries or interpreter vulnerabilities; the interpreter was separately upgraded from the official security release. Keep scan failures visible and reassess with future advisory updates.

Asset boot prints a warning about the vips backend because the native **libvips** library is not installed locally. The ruby-vips gem is explicitly locked and lazy-loaded; login, tests and assets work, and file/variant routes remain disabled. The media-processing path is not exercised or claimed verified. If enabled later, provision and security-review native libvips separately and test actual variants; no package was installed on Hetzner.

Production remains blocked on the previously documented infrastructure provisioning, reviewed role/connection grants, encrypted off-host backup/restore proof, DNS/TLS checks, operator account, alerting and explicit deployment/migration approvals. The dependency-audit blocker is resolved. Server-side changes proposed by P1.1a now require Ruby **3.4.12**, RubyGems/Bundler **4.1.0**, this locked bundle, and the additive queue migration; nothing has been applied. See the [updated runbook](../p1.1/deployment-runbook.md).
