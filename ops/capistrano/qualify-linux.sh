#!/usr/bin/env bash
# Run only on an ephemeral GitHub-hosted Ubuntu runner using fixture credentials.
set -euo pipefail
[[ ${RUNNER_OS:-} == Linux && ${RUNNER_ENVIRONMENT:-} == github-hosted && ${GITHUB_ACTIONS:-} == true ]]
work=$(mktemp -d /tmp/muzeum-cutover.XXXXXX)
chmod 0755 "$work"
trap 'sudo journalctl -u muzeum-web -u muzeum-worker -u muzeum-qualification-caddy --no-pager -n 35' ERR
base=c37a00dcf058e87fdc59644e9e444c001e29622f
candidate=96597aa6f94e64b6bb9cfdb7399de1ed98124a11
successor=906a7994cb078847c403716dde4fea18288b2218
app=/var/www/muzeum
runtime=/opt/muzeum/ruby-3.4.13/bin
bundle_path=$app/shared/bundle/ruby-3.4.13
deploy=muzeum-deploy
for account in "$deploy" muzeum-migrate; do
  sudo useradd -m -s /bin/bash "$account"
done
sudo install -d -m 0755 "$(dirname "$runtime")"
sudo ln -s "$(dirname "$(command -v ruby)")" "$runtime"
sudo install -d -o "$deploy" -m 0755 "$app" "$app/releases" "$app/shared" \
  "$app/shared/tmp" "$app/shared/public" "$app/shared/public/assets" "$app/shared/bundle"
for directory in storage log tmp/pids tmp/sockets; do
  sudo install -d -o muzeum -m 0755 "$app/shared/$directory"
done
sudo install -d -o "$deploy" -m 0755 "$bundle_path"
cached_bundle=$(bundle exec ruby -e 'puts Bundler.bundle_path')
test -d "$cached_bundle/gems"
sudo cp -a "$cached_bundle/../../." "$bundle_path/"
sudo chown -R "$deploy:$deploy" "$bundle_path"
mkdir "$work/controls"
tar --exclude=./vendor/bundle --exclude=./.bundle -cf - . | tar -xf - -C "$work/controls"
sudo chown -R "$deploy:$deploy" "$work/controls"
sudo -u "$deploy" git clone --mirror --no-local "$work/controls" "$app/repo"
for revision in "$base" "$candidate" "$successor"; do
  sudo -u "$deploy" git --git-dir="$app/repo" cat-file -e "$revision^{commit}"
done
# Exercise the same SSH transport with the runner's independently known host key.
ssh_dir=/home/$deploy/.ssh
sudo install -d -m 0700 -o "$deploy" "$ssh_dir"
sudo -u "$deploy" ssh-keygen -q -t ed25519 -N "" -f "$ssh_dir/id_ed25519"
sudo -u "$deploy" cp "$ssh_dir/id_ed25519.pub" "$ssh_dir/authorized_keys"
sudo chmod 0600 "$ssh_dir/authorized_keys" "$ssh_dir/id_ed25519"
printf '127.0.0.1 %s\n' "$(cat /etc/ssh/ssh_host_ed25519_key.pub)" |
  sudo -u "$deploy" tee "$ssh_dir/known_hosts" >/dev/null
sudo systemctl start ssh
sudo -u "$deploy" ssh -o BatchMode=yes -o StrictHostKeyChecking=yes 127.0.0.1 true
cat <<'RUBY' | sudo -u "$deploy" tee "$work/controls/ops/capistrano/config/deploy/qualification.rb" >/dev/null
server "127.0.0.1", user: "muzeum-deploy", roles: %w[app web],
  ssh_options: { keys: ["/home/muzeum-deploy/.ssh/id_ed25519"], keys_only: true }
RUBY
cap_select() {
  sudo -u "$deploy" env PATH="$runtime:/usr/bin:/bin" BUNDLE_PATH="$bundle_path" BUNDLE_IGNORE_CONFIG=1 \
    MUZEUM_STAGED_RELEASE="$1" MUZEUM_REVISION="$2" MUZEUM_BASELINE="$3" \
    bash -c 'cd "$1/controls/ops/capistrano"; exec bundle exec cap qualification muzeum:select' _ "$work"
}
for entry in "20261121000000:$base" "20261122000000:$candidate" "20261123000000:$successor"; do
  timestamp=${entry%%:*}
  revision=${entry#*:}
  release=$app/releases/$timestamp
  sudo -u "$deploy" mkdir "$release"
  git --no-replace-objects archive "$revision" | sudo -u "$deploy" tar -xf - -C "$release"
  printf '%s\n' "$revision" | sudo -u "$deploy" tee "$release/REVISION" >/dev/null
  for link in .env storage log tmp/pids tmp/sockets public/assets; do
    sudo -u "$deploy" rm -rf -- "$release/$link"
    sudo -u "$deploy" ln -s "$app/shared/$link" "$release/$link"
  done
done
sudo -u "$deploy" ln -s "$app/releases/20261121000000" "$app/current"
for identity in muzeum muzeum-migrate; do
  for path in "$app" "$app/releases" "$app/current/config/boot.rb" "$bundle_path" "$app/shared/public/assets"; do
    sudo -u "$identity" test ! -w "$path"
  done
  sudo -u "$identity" test -r "$app/current/config/boot.rb"
done
# Reject modified code even if the staged REVISION still carries the approved SHA.
boot=$app/releases/20261122000000/config/boot.rb
printf '\n# fixture substitution\n' | sudo -u "$deploy" tee -a "$boot" >/dev/null
if cap_select 20261122000000 "$candidate" "$base" > "$work/modified-tree.log" 2>&1; then
  echo 'Modified tree unexpectedly accepted' >&2
  exit 1
fi
cat "$work/modified-tree.log"
grep -q "config/boot.rb: needs update" "$work/modified-tree.log"
test "$(cat "$app/current/REVISION")" = "$base"
git show "$candidate:config/boot.rb" | sudo -u "$deploy" tee "$boot" >/dev/null

export PGHOST=127.0.0.1 PGUSER=postgres PGPASSWORD=postgres
psql -X -v ON_ERROR_STOP=1 -d postgres <<'SQL'
CREATE ROLE muzeum_runtime LOGIN PASSWORD 'runtime-fixture';
CREATE ROLE muzeum_migrator LOGIN PASSWORD 'migrator-fixture';
CREATE ROLE muzeum_owner NOLOGIN;
SQL
for database in primary cache queue cable; do
  case "$database" in primary) name=muzeum_production ;; *) name=muzeum_production_$database ;; esac
  createdb "$name"
done
env_file=$work/runtime.env
cat > "$env_file" <<'ENV'
RAILS_ENV=production
SECRET_KEY_BASE=disposable-qualification-fixture-secret-with-no-production-access
DATABASE_URL=postgresql://muzeum_runtime:runtime-fixture@127.0.0.1/muzeum_production
CACHE_DATABASE_URL=postgresql://muzeum_runtime:runtime-fixture@127.0.0.1/muzeum_production_cache
QUEUE_DATABASE_URL=postgresql://muzeum_runtime:runtime-fixture@127.0.0.1/muzeum_production_queue
CABLE_DATABASE_URL=postgresql://muzeum_runtime:runtime-fixture@127.0.0.1/muzeum_production_cable
ENV
sudo install -m 0600 "$env_file" "$app/shared/.env"
set -a
source "$env_file"
set +a
rails_as() (
  identity=$1
  directory=$2
  shift 2
  cd "$directory"
  sudo -u "$identity" env PATH="$runtime:/usr/bin:/bin" RAILS_ENV=production \
    SECRET_KEY_BASE="$SECRET_KEY_BASE" DATABASE_URL="$DATABASE_URL" CACHE_DATABASE_URL="$CACHE_DATABASE_URL" \
    QUEUE_DATABASE_URL="$QUEUE_DATABASE_URL" CABLE_DATABASE_URL="$CABLE_DATABASE_URL" \
    BUNDLE_PATH="$bundle_path" BUNDLE_IGNORE_CONFIG=1 BUNDLE_DEPLOYMENT=true BUNDLE_FROZEN=true \
    BUNDLE_WITHOUT=development:test DISABLE_BOOTSNAP=1 VERSION="${VERSION:-}" \
    PGOPTIONS='-c lock_timeout=5000 -c statement_timeout=120000' \
    "$runtime/ruby" "$runtime/bundle" exec rails "$@"
)
(
  for variable in DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL; do
    export "$variable=${!variable/muzeum_runtime:runtime-fixture/postgres:postgres}"
  done
  rails_as "$deploy" "$app/current" db:migrate:primary
  rails_as "$deploy" "$app/current" runner '
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "restore-fixture")
    user.sessions.create!(grant_token: "disposable-recovery-fixture",
      expires_at: 1.day.from_now, last_seen_at: Time.current, verified_at: Time.current)'
  rails_as "$deploy" "$app/current" runner '
    %w[cache queue cable].each do |name|
      config = ActiveRecord::Base.configurations.configs_for(env_name: "production", name: name)
      ActiveRecord::Base.establish_connection(config)
      load Rails.root.join("db", "#{name}_schema.rb")
    end'
)
for database in muzeum_production{,_cache,_queue,_cable}; do
  psql -X -v ON_ERROR_STOP=1 -d "$database" -c '
    GRANT USAGE ON SCHEMA public TO muzeum_runtime;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO muzeum_runtime;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO muzeum_runtime;'
done
psql -X -v ON_ERROR_STOP=1 -d muzeum_production <<'SQL'
GRANT USAGE, CREATE ON SCHEMA public TO muzeum_migrator;
ALTER TABLE resolution_decisions OWNER TO muzeum_migrator;
GRANT SELECT, INSERT ON schema_migrations TO muzeum_migrator;
GRANT SELECT, INSERT, UPDATE ON ar_internal_metadata TO muzeum_migrator;
SQL
for unit in muzeum-web muzeum-worker; do
  sudo install -m 0644 "config/deploy/templates/$unit.service" "/etc/systemd/system/$unit.service"
  sudo install -D -m 0644 "ops/capistrano/systemd/$unit.service.d/30-capistrano.conf" "/etc/systemd/system/$unit.service.d/30-capistrano.conf"
done
sudo apt-get install -y caddy postgresql-client-16
sudo systemctl stop caddy
sudo tee /etc/systemd/system/muzeum-qualification-caddy.service >/dev/null <<'UNIT'
[Service]
ExecStart=/usr/bin/caddy run --config /etc/muzeum-qualification-Caddyfile --adapter caddyfile
UNIT
write_route() {
  {
    printf '{\n auto_https off\n}\nhttp://auth.fixture:8099 {\n respond "neighbor unchanged"\n}\n'
    if [[ $1 == active ]]; then
      printf 'http://muzeum.fm:8099 {\n reverse_proxy 127.0.0.1:3011\n}\n'
    fi
  } | sudo tee /etc/muzeum-qualification-Caddyfile >/dev/null
}
reload_route() {
  write_route "$1"
  sudo caddy validate --config /etc/muzeum-qualification-Caddyfile --adapter caddyfile
  sudo caddy reload --config /etc/muzeum-qualification-Caddyfile --adapter caddyfile
}
neighbor() {
  curl -fsS -H 'Host: auth.fixture' http://127.0.0.1:8099 | grep -qx 'neighbor unchanged'
  test "$(systemctl show -p MainPID --value muzeum-qualification-caddy)" = "$caddy_pid"
}
health() {
  sudo systemctl is-active muzeum-web muzeum-worker
  curl -fsS --retry 12 --retry-all-errors --retry-delay 2 -H 'Host: muzeum.fm' http://127.0.0.1:3011/up
  for attempt in {1..15}; do
    if [[ $(psql -XAt -d muzeum_production_queue -c "SELECT count(DISTINCT kind) FROM solid_queue_processes WHERE last_heartbeat_at > now()-interval '30 seconds'") -ge 3 ]]; then
      return
    fi
    sleep 2
  done
  return 1
}
write_route active
sudo systemctl daemon-reload
sudo systemctl start muzeum-qualification-caddy muzeum-web muzeum-worker
caddy_pid=$(systemctl show -p MainPID --value muzeum-qualification-caddy)
health
neighbor
reload_route withdrawn
neighbor
sudo systemctl stop muzeum-web muzeum-worker
export RESTIC_REPOSITORY="$work/restic" RESTIC_PASSWORD=disposable-fixture-password
mkdir -p "$work/backup"
restic init
verify_recovery() {
  local revision=$1 database snapshot restored target suffix
  for database in muzeum_production{,_cache,_queue,_cable}; do
    pg_dump -Fc "$database" > "$work/backup/$database.dump"
  done
  mkdir -p "$work/backup/files/var/www/muzeum/shared"
  cp "$env_file" "$work/backup/files/var/www/muzeum/shared/.env"
  jq -n --arg revision "$revision" '{release_sha: $revision}' > "$work/backup/production.json"
  restic backup "$work/backup" --tag "$revision"
  snapshot=$(restic snapshots --json --tag "$revision" | jq -er '.[-1].id')
  restic restore "$snapshot" --target "$work/recovery" --verify
  suffix=$(openssl rand -hex 6)
  for database in muzeum_production{,_cache,_queue,_cable}; do
    case "$database" in
      muzeum_production) target=muzeum_recovery_"${suffix}0000" ;;
      muzeum_production_cache) target=muzeum_recovery_"${suffix}0001" ;;
      muzeum_production_queue) target=muzeum_recovery_"${suffix}0002" ;;
      muzeum_production_cable) target=muzeum_recovery_"${suffix}0003" ;;
    esac
    createdb "$target"
    restored="$work/recovery$work/backup/$database.dump"
    cmp "$work/backup/$database.dump" "$restored"
    pg_restore --exit-on-error -d "$target" "$restored"
    test "$(psql -XAt -d "$target" -c 'SELECT count(*) FROM schema_migrations')" =       "$(psql -XAt -d "$database" -c 'SELECT count(*) FROM schema_migrations')"
  done
  sudo env PGHOST="$PGHOST" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" python3 -IB - "$PWD" "$work/recovery$work/backup" "$revision" "$suffix" <<'PYTHON'
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / 'ops/backups'))
import production_restore

targets = {name: f'muzeum_recovery_{sys.argv[4]}{number:04d}'
           for number, name in enumerate(production_restore.production_capture.DATABASES)}

def invoke(argv, **kwargs):
    # The qualification server is the CI PostgreSQL container rather than a host socket.
    subprocess.run(argv[4:], check=True, **kwargs)

restored = Path(sys.argv[2])
metadata = json.loads((restored / 'production.json').read_text())
assert metadata['release_sha'] == sys.argv[3]
proof = production_restore.verify_application(restored, targets, metadata, invoke)
assert proof['grant_decryption_verified'] is True and proof['sessions'] == 1
PYTHON
  echo "Fixed-runtime recovery verified for $revision in encrypted snapshot $snapshot"
}
verify_recovery "$base"
(
  export DATABASE_URL=${DATABASE_URL/muzeum_runtime:runtime-fixture/muzeum_migrator:migrator-fixture}
  export VERSION=20261121160000
  rails_as muzeum-migrate "$app/releases/20261122000000" db:migrate:up:primary
)
test "$(psql -XAt -d muzeum_production -c "SELECT indisvalid AND indisready FROM pg_index WHERE indexrelid='index_resolution_decisions_on_recording_and_listener'::regclass")" = t
for entry in "20261122000000:$candidate:$base" "20261121000000:$base:$candidate" "20261123000000:$successor:$base"; do
  IFS=: read -r timestamp revision previous <<< "$entry"
  cap_select "$timestamp" "$revision" "$previous"
  test "$(cat "$app/current/REVISION")" = "$revision"
  sudo systemctl restart muzeum-web muzeum-worker
  health
  sudo python3 -IB ops/provision/check-runtime.py status |
    sed -n '/^{"observed_at":/p' |
    jq -es --arg sha "$revision" 'length == 1 and .[0].revision == $sha'
  if [[ $revision != "$base" ]]; then
    rails_as muzeum "$app/current" runner - < ops/deploy/inspect.rb |
      sed -n 's/^MUZEUM_DEPLOY_INSPECTION://p' |
      jq -es 'length == 1 and (.[0].databases | length) == 4 and .[0].pending == []'
  fi
  reload_route active
  curl -fsS -H 'Host: muzeum.fm' http://127.0.0.1:8099/up
  neighbor
  test "$(psql -XAt -d muzeum_production -c "SELECT indisvalid FROM pg_index WHERE indexrelid='index_resolution_decisions_on_recording_and_listener'::regclass")" = t
  echo "Qualified live artifact $revision"
  if [[ $revision == "$successor" ]]; then
    reload_route withdrawn
    sudo systemctl stop muzeum-web muzeum-worker
    verify_recovery "$revision"
    sudo systemctl start muzeum-web muzeum-worker
    health
    reload_route active
    neighbor
  fi
done
