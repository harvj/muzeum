# Seed only an explicitly named disposable pre-P1.2 schema, using synthetic fixtures.
require "pg"
require "json"
require "digest"
require "time"
uri = ENV.fetch("DATABASE_URL")
connection = PG.connect(uri)
abort "Synthetic legacy rehearsal DB required" unless connection.db == "muzeum_p12_legacy_migration"
folder = File.expand_path(ENV.fetch("FIXTURE_DIR"))
manifest = JSON.parse(File.read(File.join(folder, "manifest.json")))
connection.exec("INSERT INTO users(id,lastfm_username,oidc_issuer,oidc_subject,created_at,updated_at) VALUES(1,'synthetic','https://auth.harvj.com','preserved-synthetic-subject','2026-01-01','2026-01-01')")
connection.exec_params("INSERT INTO import_runs(id,user_id,status,source_username,upper_bound,total_pages,expected_count,next_page,scrobbles_processed,last_success_at,created_at,updated_at) VALUES(1,1,2,'synthetic',$1,$2,$3::bigint,$4,$3::integer,'2026-01-01','2026-01-01','2026-01-01')",
  [ manifest.fetch("last_timestamp") + 1, manifest.fetch("pages"), manifest.fetch("count"), manifest.fetch("pages") + 1 ])
manifest.fetch("pages").times do |offset|
  number = offset + 1
  raw = File.read(File.join(folder, format("%05d.xml", number)))
  connection.exec_params("INSERT INTO import_pages(id,import_run_id,number,raw_body,checksum,created_at,updated_at) VALUES($1::bigint,1,$1::integer,$2,$3,'2026-01-01','2026-01-01')", [ number, raw, Digest::SHA256.hexdigest(raw) ])
  items = JSON.parse(File.read(File.join(folder, format("%05d.json", number))))
  parameters = []; values = []
  items.each do |item|
    payload = item.fetch("payload")
    seconds = payload.fetch("played_at")
    fp = Digest::SHA256.hexdigest(JSON.generate([ "synthetic", seconds, payload["artist_name"], payload["album_name"], payload["track_name"] ]))
    payload["played_at"] = Time.at(seconds).utc.iso8601(3)
    id = (seconds - manifest.fetch("first_timestamp")) / 2100 + 1
    start = parameters.length
    parameters.concat([ id, Time.at(seconds).utc, JSON.generate(payload), fp, number ])
    placeholders = (1..5).map { |index| "$#{start + index}" }
    values << "(#{placeholders[0]},1,#{placeholders[1]},#{placeholders[2]},#{placeholders[3]},#{placeholders[4]},'2026-01-01','2026-01-01')"
  end
  connection.exec_params("INSERT INTO scrobbles(id,user_id,played_at,payload,source_fingerprint,import_page_id,created_at,updated_at) VALUES #{values.join(',')}", parameters)
end
%w[users import_runs import_pages scrobbles].each { |table| connection.exec("SELECT setval(pg_get_serial_sequence('#{table}','id'),(SELECT max(id) FROM #{table}))") }
puts "Seeded #{manifest.fetch('count')} synthetic preserved-ID observations in a legacy schema."
