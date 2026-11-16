# P1.0 — Executable baseline results

Executed 2026-11-15 against unchanged application commit `3fa3e0a076699c4ff21967805984eb60f25c5b20`. No application/schema/test/deployment corrections were made. This report records the original results, including failures, before future P1.1 changes. Captured transcripts have trailing whitespace and extra blank end lines removed; diagnostic content is unchanged.

## Environment

- macOS arm64; rbenv Ruby **3.3.5** installed using `rbenv install 3.3.5` (OpenSSL/libyaml/gmp from Homebrew). The pin was not changed.
- `bundle install` installed the locked dependencies and Bundler **4.0.3**; `bundle check` succeeds. Gemfile and Gemfile.lock remain unchanged. Rails **8.1.2**.
- Disposable PostgreSQL **16.15**, data directory `/tmp/muzeum-p10-postgres`, port **56487**, localhost only. Separate `muzeum_p10_schema` and `muzeum_p10_migrate` databases. No development or production database connections.
- Initial sandbox initdb failed on shared memory; approved execution outside the sandbox succeeded. Port 55439 was occupied; this task used 56487 and did not interfere with the existing server.
- No live provider credentials or calls. WebMock disables external connections in the suite. The fixture diagnostic below substitutes a local MusicBrainz response and rolls back its entire transaction.
- The disposable cluster was stopped after verification; its files remain under /tmp for optional inspection. Ruby and the installed locked gems remain available locally.

## Original check results

| Check | Result | Evidence |
| --- | --- | --- |
| Dependency availability | Pass, pinned Ruby and lockfile activated | Versions above; no dependency changes |
| Existing schema load | Pass | Existing schema loaded into isolated schema DB |
| Full migration replay | Pass | [Transcript](baseline/migration-replay.txt) |
| Migrated schema vs committed schema | Identical, `diff -u` exit 0 | Dump written under /tmp; db/schema.rb unchanged |
| RSpec on schema-loaded DB | **49 examples, 0 failures**, 0.560s examples (0.635s load) | [Detailed output](baseline/rspec-schema.txt) |
| RSpec on migration-built DB | **49 examples, 0 failures**, 0.502s examples (1.33s load) | [Output](baseline/rspec-migrated.txt) |
| Zeitwerk eager loading | Pass | [Output](baseline/zeitwerk.txt) |
| RuboCop | **73 files, no offenses**, exit 0 | [Output](baseline/rubocop.txt); /tmp symlink cache warnings only |
| Brakeman 8.0.1 | **0 errors, 0 warnings**, normal strict command exit 0 | [Output](baseline/brakeman.txt) |
| Dependency audit with refreshed DB | **Fail, exit 1; 237 advisory findings across 22 locked gems** | [Full findings](baseline/dependency-audit.txt) |

The advisory database revision was `5755673fdd52efd87217e72b9a2e0619ceeee889`. This is scanner output, not 237 independently verified exploitable application paths. Findings include Rails components, Rack/session, Nokogiri, Puma and transitive dependencies. No advisories were suppressed and no dependencies upgraded. Security upgrade/verification is an explicit follow-up before exposing authenticated write endpoints or deploying. Brakeman's clean static result does not supersede the dependency audit. The configured `bin/bundler-audit` placeholder ignore is not a substantive mitigation.

### Diagnostic findings despite green specs

Using real fixture data and explicit service invocations inside a rolled-back transaction:

1. Resolving one unresolved event twice changes surface observed_count **1 → 2**.
2. Calling ReleaseIngestor twice with a persisted/reloaded selection raises **ActiveRecord::RecordNotUnique**, on `index_release_recordings_on_release_id_and_position`.
3. Artist.releases, Recording.releases and Release.recordings have no `through` option; their inferred foreign keys do not match the intended joins.

The current retry spec memoizes `subject(:ingest!)`; its second reference returns the prior result instead of executing ingestion. The current resolver no-op spec checks entity counts, not observed_count. These are actual test gaps, not a claim that the suite failed. No fixes were made because P1.0 permits environment corrections only. [Diagnostic source](baseline/diagnostic.rb.txt) and [output](baseline/diagnostic-result.txt) are retained for reproduction, not installed application code.

## Reproduction

Use fresh disposable directories/databases and a free port; do not point these commands at a populated development or production DB. The initial cluster uses trust authentication on localhost solely for disposable testing. Setup/install require local tool and network permissions.

```sh
rbenv install -s 3.3.5
bundle install
ruby -v
bundle --version
bundle check

/opt/homebrew/opt/postgresql@16/bin/initdb -D /tmp/muzeum-p10-postgres -A trust --no-locale -E UTF8
/opt/homebrew/opt/postgresql@16/bin/pg_ctl -D /tmp/muzeum-p10-postgres -l /tmp/muzeum-p10-postgres.log -o '-p 56487 -h 127.0.0.1 -k /tmp' start
/opt/homebrew/opt/postgresql@16/bin/createdb -h 127.0.0.1 -p 56487 muzeum_p10_schema
/opt/homebrew/opt/postgresql@16/bin/createdb -h 127.0.0.1 -p 56487 muzeum_p10_migrate

export RAILS_ENV=test
export DATABASE_URL=postgresql://jim@127.0.0.1:56487/muzeum_p10_schema
bundle exec rails db:schema:load
bundle exec rspec --format documentation
bundle exec rails zeitwerk:check

env DATABASE_URL=postgresql://jim@127.0.0.1:56487/muzeum_p10_migrate SCHEMA=/tmp/muzeum-p10-migrated-schema.rb bundle exec rails db:migrate
diff -u db/schema.rb /tmp/muzeum-p10-migrated-schema.rb
env DATABASE_URL=postgresql://jim@127.0.0.1:56487/muzeum_p10_migrate bundle exec rspec

env RUBOCOP_CACHE_ROOT=/private/tmp/muzeum-p10-rubocop bundle exec rubocop --format simple
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
```

Substitute your local PostgreSQL role for `jim` on another machine. Reuse an existing cluster only if it is known to be this task's disposable cluster. `--update` makes future audit findings time-dependent; the checked-in report pins the reviewed DB revision. For a historical repeat, use an isolated advisory DB checkout at that revision and bundler-audit's `--database` option rather than resetting a shared advisory DB.

To rerun the diagnostic, copy `baseline/diagnostic.rb.txt` to a temporary `.rb` file and use `bundle exec rails runner /path/to/copied.rb` with the schema DB URL above. Its transaction raises ActiveRecord::Rollback deliberately. No benchmark harness or new production pipeline was implemented. The 250k requirements remain proposed gates in [the import plan](import-requirements.md).
