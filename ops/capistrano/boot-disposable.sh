#!/usr/bin/env bash
set -euo pipefail
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
app=/var/www/muzeum
test -f "$app/.muzeum-disposable"
sudo useradd --system --user-group muzeum
sudo install -d -o muzeum -g muzeum "$app/shared/tmp/"{pids,sockets,storage}
sudo chown muzeum:muzeum "$app/shared/"{tmp,log,storage}
export PGHOST=127.0.0.1 PGUSER=postgres PGPASSWORD=postgres
psql -X -v ON_ERROR_STOP=1 -d postgres -c "CREATE ROLE muzeum_fixture LOGIN PASSWORD 'disposable-fixture';"
for db in primary cache queue cable; do createdb "muzeum_fixture_$db"; done
{
  echo 'RAILS_ENV=production'
  echo 'SECRET_KEY_BASE=untrusted-disposable-github-actions-fixture'
  for pair in DATABASE:primary CACHE_DATABASE:cache QUEUE_DATABASE:queue CABLE_DATABASE:cable; do
    printf '%s_URL=postgresql://muzeum_fixture:disposable-fixture@127.0.0.1/muzeum_fixture_%s\n' "${pair%:*}" "${pair#*:}"
  done
} > "$app/shared/.env"
for unit in muzeum-web muzeum-worker; do
  sudo install -m 0644 "config/deploy/templates/$unit.service" "/etc/systemd/system/$unit.service"
  sudo install -D -m 0644 "ops/capistrano/systemd/$unit.service.d/30-capistrano.conf" "/etc/systemd/system/$unit.service.d/30-capistrano.conf"
done
sudo systemctl daemon-reload
sudo systemd-run --unit=muzeum-fixture-neighbor /usr/bin/sleep 1800
neighbor=$(systemctl show -p MainPID --value muzeum-fixture-neighbor)
set -a
source "$app/shared/.env"
set +a
for link in DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL; do
  export "$link=${!link/muzeum_fixture:disposable-fixture/postgres:postgres}"
done
export BUNDLE_PATH="$app/shared/bundle/ruby-3.4.13" BUNDLE_DEPLOYMENT=true BUNDLE_FROZEN=true BUNDLE_IGNORE_CONFIG=1 BUNDLE_WITHOUT=development:test DISABLE_BOOTSNAP=1
mapfile -t releases < <(find "$app/releases" -mindepth 1 -maxdepth 1 -type d | sort)
test "${#releases[@]}" -eq 2
(
  cd "${releases[0]}"
  bundle exec rails db:migrate:primary
  bundle exec rails runner '
    %w[cache queue cable].each do |name|
      config = ActiveRecord::Base.configurations.configs_for(env_name: "production", name: name)
      ActiveRecord::Base.establish_connection(config)
      load Rails.root.join("db", "#{name}_schema.rb")
    end'
)
(
  cd "${releases[1]}"
  bundle exec rails db:migrate:primary
)
for db in primary cache queue cable; do
  psql -X -v ON_ERROR_STOP=1 -d "muzeum_fixture_$db" -c '
    GRANT USAGE ON SCHEMA public TO muzeum_fixture;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO muzeum_fixture;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO muzeum_fixture;'
done
for release in "${releases[@]}"; do
  revision=$(cat "$release/REVISION")
  before=$(ruby "$release/script/muzeum_release_identity.rb" verify "$revision")
  ln -sfn "$release" "$app/current"
  sudo systemctl restart muzeum-web muzeum-worker
  curl -fsS --retry 15 --retry-all-errors --retry-delay 2 -H 'Host: muzeum.fm' http://127.0.0.1:3011/up
  for attempt in {1..15}; do
    count=$(psql -XAt -d muzeum_fixture_queue -c "SELECT count(DISTINCT kind) FROM solid_queue_processes WHERE last_heartbeat_at > now()-interval '15 seconds'")
    [[ $count -ge 3 ]] && break
    sleep 2
  done
  [[ $count -ge 3 ]]
  systemctl is-active muzeum-web muzeum-worker
  test "$(systemctl show -p MainPID --value muzeum-fixture-neighbor)" = "$neighbor"
  test "$(ruby "$release/script/muzeum_release_identity.rb" verify "$revision")" = "$before"
  echo "Healthy sealed release: $before"
done
