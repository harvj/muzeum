# Standalone read-only digest usable before/after migrations and restoration.
require "pg"
require "json"
require "digest"
connection = PG.connect(ENV.fetch("DATABASE_URL"))
abort "Dedicated synthetic verification DB required" unless connection.db.start_with?("muzeum_p12_")
output = { database: connection.db }
connection.exec("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY")
%w[scrobbles import_pages].each do |table|
  digest = Digest::SHA256.new; count = 0
  fields = table == "scrobbles" ? "id,user_id,played_at,payload,source_fingerprint,import_page_id,created_at" : "id,import_run_id,number,raw_body,checksum,created_at"
  connection.exec("DECLARE evidence_cursor NO SCROLL CURSOR FOR SELECT #{fields} FROM #{table} ORDER BY id")
  loop do
    rows = connection.exec("FETCH 1000 FROM evidence_cursor")
    break if rows.ntuples.zero?
    rows.each { |row| digest << JSON.generate(row) << "\n"; count += 1 }
  end
  connection.exec("CLOSE evidence_cursor")
  output[table] = { count: count, sha256: digest.hexdigest }
end
output[:principals] = connection.exec("SELECT id,oidc_issuer,oidc_subject,lastfm_username FROM users ORDER BY id").to_a
output[:checkpoints] = connection.exec("SELECT id,user_id,status,next_page,upper_bound,total_pages,expected_count,scrobbles_processed,last_success_at,source_username FROM import_runs ORDER BY id").to_a
connection.exec("COMMIT")
puts JSON.pretty_generate(output)
