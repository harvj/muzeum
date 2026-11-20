#!/bin/bash
set -euo pipefail
work=$(mktemp -d /tmp/muzeum-final-recovery.XXXXXX)
export PATH="/usr/lib/postgresql/16/bin:$PATH"
source_checkout=$PWD
mkdir "$work/baseline" "$work/target"
git -C "$BASELINE_CHECKOUT" archive HEAD | tar -x -C "$work/baseline"
git archive HEAD | tar -x -C "$work/target"

export PGUSER=postgres PGHOST=127.0.0.1 RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1
port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
export PGPORT=$(port)
export PORT=$(port)
mkdir "$work/sock"
initdb -A trust -U postgres --no-locale --encoding=UTF8 -D "$work/pg" >"$work/init.log"
pg_ctl -D "$work/pg" -l "$work/pg.log" -o "-p $PGPORT -h 127.0.0.1 -k $work/sock" -w start
web= queue=
stop() {
 local pid
 for pid in "$web" "$queue"; do
  if [ -n "$pid" ]; then kill -TERM "$pid" 2>/dev/null || true; wait "$pid" || true; fi
 done
 web= queue=
}
trap 'stop; pg_ctl -D "$work/pg" -m fast -w stop' EXIT
for db in primary cache queue cable; do createdb "$db"; done
export DATABASE_URL="postgresql://postgres@127.0.0.1:$PGPORT/primary"
export CACHE_DATABASE_URL="postgresql://postgres@127.0.0.1:$PGPORT/cache"
export QUEUE_DATABASE_URL="postgresql://postgres@127.0.0.1:$PGPORT/queue"
export CABLE_DATABASE_URL="postgresql://postgres@127.0.0.1:$PGPORT/cable"
cd "$work/baseline"
bundle exec rails runner ' %w[cache queue cable].each { |name| ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations.configs_for(env_name: "production", name: name)); load Rails.root.join("db", name + "_schema.rb") }' >"$work/schema.log" 2>&1
bundle exec rails db:migrate:primary >>"$work/schema.log" 2>&1
for db in primary cache queue cable; do
 pg_dump -Fc "$db" >"$work/$db.dump"
 createdb "restored_$db"
 pg_restore --exit-on-error -d "restored_$db" "$work/$db.dump"
done
for db in primary cache queue cable; do
 key="$(echo "$db" | tr a-z A-Z)_DATABASE_URL"
 if [ "$db" = primary ]; then key=DATABASE_URL; fi
 export "$key=postgresql://postgres@127.0.0.1:$PGPORT/restored_$db"
done
cd "$work/target"
bundle exec rails db:migrate:primary >"$work/candidate-migrate.log" 2>&1
for release in target; do
 ln -sfn "$work/$release" "$work/current"
 cd "$work/current"
 bundle exec rails assets:precompile >"$work/$release-assets.log" 2>&1
 bundle exec puma -C config/puma.rb >"$work/$release-web.log" 2>&1 &
 web=$!
 bundle exec ruby bin/jobs >"$work/$release-queue.log" 2>&1 &
 queue=$!
 for ((i=0;i<100;i++)); do
  health=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: muzeum.fm' -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/up" || true)
  kinds=$(psql -d restored_queue -Atc "SELECT count(DISTINCT kind) FROM solid_queue_processes WHERE last_heartbeat_at > (now() AT TIME ZONE 'UTC') - interval '30 seconds'")
  if [ "$health" = 200 ] && [ "$kinds" = 4 ]; then break; fi
  kill -0 "$web" "$queue"
  sleep .25
 done
 echo "$release HTTP=$health process_kinds=$kinds"; if [ "$health" != 200 ]; then tail -30 "$work/$release-web.log"; fi
 test "$health" = 200 && test "$kinds" = 4
 bundle exec rails runner 'abort unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter); puts "Scrobbles=#{Scrobble.count}"'
 reference=$(openssl rand -hex 16)
 export REHEARSAL_REFERENCE="$reference"
 bundle exec rails runner 'OpsProbeJob.perform_later(ENV.fetch("REHEARSAL_REFERENCE"))'
 for ((i=0;i<40;i++)); do
  if bundle exec rails runner 'abort unless Rails.cache.read("muzeum/worker-probe/#{ENV.fetch("REHEARSAL_REFERENCE")}")' >"$work/$release-probe.log" 2>&1; then
   echo "$release executed shipped OpsProbeJob and wrote to restored Solid Cache"
   break
  fi
  sleep .25
 done
 if [ "$i" -ge 40 ]; then tail -60 "$work/$release-queue.log"; exit 1; fi
 stop
done
