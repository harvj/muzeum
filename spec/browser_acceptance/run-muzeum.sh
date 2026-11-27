#!/usr/bin/env bash
set -euo pipefail
umask 077
suite="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(git -C "$suite" rev-parse --show-toplevel)"
root="${MUZEUM_BROWSER_WORK:?Choose a new private output directory}"
auth="${AUTH_CHECKOUT:?Supply the disposable Auth source checkout}"
infra="${INFRA_CHECKOUT:?Supply the Infrastructure pilot checkout}"
archive="${MUZEUM_CANDIDATE_ARCHIVE:?Supply the verified disposable Capistrano archive}"
revision="${MUZEUM_CANDIDATE_SHA:?Supply the exact Muzeum revision}"
expected_digest="${MUZEUM_SEALED_DIGEST:?Supply the independently verified sealed inventory digest}"
expected_archive_digest="${MUZEUM_ARCHIVE_DIGEST:?Supply the retained archive digest}"
playwright="${PLAYWRIGHT_NODE_MODULES:?Supply the Playwright Core node_modules directory}"
[[ "$revision" =~ ^[0-9a-f]{40}$ && "$expected_digest" =~ ^[0-9a-f]{64}$ && "$expected_archive_digest" =~ ^[0-9a-f]{64}$ ]]
if [[ "$(git -C "$repo" rev-parse HEAD)" != "$revision" ]] ||
  [[ -n "$(git -C "$repo" status --porcelain -- spec/browser_acceptance spec/support/public_profile_fixture.rb)" ]]; then
  echo "Use the exact candidate checkout with unmodified browser acceptance inputs" >&2
  exit 1
fi
test "$(shasum -a 256 "$archive" | cut -d' ' -f1)" = "$expected_archive_digest"
mkdir -m 700 "$root"
root="$(cd "$root" && pwd -P)"
export PILOT_RUBY="$(command -v ruby)"
export CHROME_BINARY="${CHROME_BINARY:?Supply the local Chromium executable}"
export MUZEUM_BROWSER_WORK="$root" INFRA_BROWSER_TOOLS="$infra/tools/browser-acceptance"
export MUZEUM_BROWSER_FIXTURE="$repo/spec/support/public_profile_fixture.rb"
cd "$root"
test "$(git -C "$infra" rev-parse HEAD)" = 21771e1d5690fef6509cd383933a8029b4834d77
cp "$archive" candidate.tar.gz
ln -s "$playwright" node_modules
mkdir -p layout/releases layout/shared auth-source
tar -xpzf candidate.tar.gz -C layout/releases
release=$(find "$root/layout/releases" -mindepth 1 -maxdepth 1 -type d)
for name in .env storage log tmp; do
  test "$(readlink "$release/$name")" = "/var/www/muzeum/shared/$name"
  if [[ "$name" != .env ]]; then mkdir "$root/layout/shared/$name"; fi
  ln -sfn "$root/layout/shared/$name" "$release/$name"
done
ruby "$release/script/muzeum_release_identity.rb" verify "$revision" > sealed-identity.json
jq -e --arg expected "$expected_digest" '.artifact_sha256 == $expected' sealed-identity.json >/dev/null
git -C "$auth" archive HEAD | tar -xf - -C auth-source
cp "$suite/muzeum.mjs" scenario.mjs
cp "$suite/loopback_proxy.mjs" proxy.mjs
cp "$suite/run-muzeum.sh" run.sh
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout tls.key -out tls.pem -subj '/CN=auth.harvj.com' -addext 'subjectAltName=DNS:auth.harvj.com,DNS:muzeum.fm' >tls-setup.log 2>&1
openssl x509 -in tls.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64 >spki
export SSL_CERT_FILE="$root/tls.pem"
independent='(version 1) (allow default) (deny network-outbound) (allow network-outbound (remote ip "localhost:*"))'
db_names='auth_poc_test_muzeumbrowser muzeum_browser_acceptance muzeum_browser_acceptance_cache muzeum_browser_acceptance_queue muzeum_browser_acceptance_cable'
cleanup() {
  for pid in ${pids:-}; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
  for db in ${created:-}; do dropdb -h 127.0.0.1 -p 55435 --if-exists "$db"; done
  rm -f "$root/identity.json" "$root/otp" "$root/tls.key"
}
trap cleanup EXIT
for db in $db_names; do
  createdb -h 127.0.0.1 -p 55435 "$db"
  created="${created:-} $db"
done
sandbox-exec -p "$independent" node proxy.mjs > proxy.log 2>&1 & pids=$!
(
  cd "$root/auth-source"
  export BUNDLE_GEMFILE="$root/auth-source/Gemfile"
  export DATABASE_URL=postgres://127.0.0.1:55435/auth_poc_test_muzeumbrowser AUTH_ISSUER=https://auth.harvj.com AUTH_PUBLIC_HOST=harvj.com
  exec sandbox-exec -p "$independent" bundle exec ruby "$repo/spec/browser_acceptance/native_auth.rb"
) > auth.log 2>&1 & pids="$pids $!"
for i in {1..80}; do test ! -s identity.json || break; sleep .2; done
test -s identity.json || exit 21
(
  cd "$release"
  export BUNDLE_GEMFILE="${MUZEUM_RUNTIME_GEMFILE:-$release/Gemfile}" BUNDLE_IGNORE_CONFIG=1
  export RAILS_ENV=production RAILS_LOG_LEVEL=warn SECRET_KEY_BASE="$(openssl rand -hex 64)"
  export DATABASE_URL=postgres://$(id -un)@127.0.0.1:55435/muzeum_browser_acceptance
  export CACHE_DATABASE_URL="${DATABASE_URL}_cache" QUEUE_DATABASE_URL="${DATABASE_URL}_queue" CABLE_DATABASE_URL="${DATABASE_URL}_cable"
  export OIDC_CLIENT_ID="$(jq -r .client_id "$root/identity.json")" OIDC_CLIENT_SECRET="$(jq -r .secret "$root/identity.json")"
  export OIDC_REQUIRED_ACR=urn:harvj:assurance:mfa OIDC_REDIRECT_URI=https://muzeum.fm/oidc/callback
  export RUBYOPT="-r$repo/spec/browser_acceptance/loopback_oidc_socket.rb"
  export PUMA_BIND=tcp://127.0.0.1:55493
  sandbox-exec -p "$independent" bundle exec rails db:migrate:primary
  sandbox-exec -p "$independent" bundle exec rails runner '%w[cache queue cable].each do |name|; cfg=ActiveRecord::Base.configurations.configs_for(env_name:"production",name:name); ActiveRecord::Base.establish_connection(cfg); load Rails.root.join("db","#{name}_schema.rb"); end'
  sandbox-exec -p "$independent" bundle exec rails runner "$repo/spec/browser_acceptance/seed_archive.rb"
  exec sandbox-exec -p "$independent" bundle exec puma -C config/puma.rb
) > muzeum.log 2>&1 & pids="$pids $!"
for i in {1..100}; do curl -fsS -H 'Host: muzeum.fm' http://127.0.0.1:55493/up >/dev/null 2>&1 && break; sleep .2; done
curl -fsS -H 'Host: muzeum.fm' http://127.0.0.1:55493/up >/dev/null
python3 - "$repo" "$auth" "$infra" "$revision" <<'PY'
import hashlib,json,os,pathlib,subprocess,sys
repo,auth,infra,revision=map(str,sys.argv[1:])
root=pathlib.Path.cwd()
def sha(path): return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
def git(path,*args): return subprocess.check_output(['git','-C',path,*args],text=True).strip()
files={name:sha(root/name) for name in ['proxy.mjs','run.sh','tls.pem','scenario.mjs']}
files.update({name:sha(pathlib.Path(repo,'spec/browser_acceptance',name)) for name in ['native_auth.rb','loopback_oidc_socket.rb','seed_archive.rb']})
files.update({name:sha(pathlib.Path(infra,'tools/browser-acceptance',name)) for name in ['run.mjs','native-auth.mjs']})
files['playwright-lock']=sha(root/'node_modules/.package-lock.json')
files['browser-binary']=sha(os.environ['CHROME_BINARY'])
files['runtime-gem-lock']=sha(pathlib.Path(os.environ.get('MUZEUM_RUNTIME_GEMFILE', next((root/'layout/releases').glob('*/Gemfile')))).with_name('Gemfile.lock'))
files['private_fixture_module']=sha(pathlib.Path(repo,'spec/support/public_profile_fixture.rb'))
env=dict(auth=git(auth,'rev-parse','HEAD'),infrastructure=git(infra,'rev-parse','HEAD'),networks='loopback-only',
  routes=['https://muzeum.fm','https://auth.harvj.com'], required_assurance='mfa', sealed_identity=json.loads((root/'sealed-identity.json').read_text()),files=files)
(root/'environment.json').write_text(json.dumps(env,sort_keys=True)+'\n')
binding=dict(application='muzeum',revision=revision,tree=git(repo,'rev-parse',revision+'^{tree}'),
  artifact_sha256=sha(root/'candidate.tar.gz'),environment_sha256=sha(root/'environment.json'))
(root/'binding.json').write_text(json.dumps(binding,sort_keys=True)+'\n')
PY
sandbox-exec -p "$independent" node scenario.mjs
test "$(psql -XAt -h 127.0.0.1 -p 55435 -d muzeum_browser_acceptance -c 'SELECT count(*) FROM sessions')" = 0
test "$(psql -XAt -h 127.0.0.1 -p 55435 -d auth_poc_test_muzeumbrowser -c 'SELECT count(*) > 0 AND bool_and(revoked_at IS NOT NULL) FROM oauth_grants')" = t
ruby "$release/script/muzeum_release_identity.rb" verify "$revision" | diff - sealed-identity.json
