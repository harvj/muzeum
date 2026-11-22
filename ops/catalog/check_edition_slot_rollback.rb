abort "Expected disposable test database" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database.match?(/\Amuzeum_edition_rollback(?:_\d+)?_test\z/)
require "action_dispatch/testing/integration"
require "action_dispatch/testing/test_request"
release_id, recording_id, user_id, overlap_id = File.read(ARGV.fetch(0)).strip.split(",").map(&:to_i)
release = Release.find(release_id)
recording = Recording.find(recording_id)
user = User.find(user_id)
session = user.sessions.create!(expires_at: 1.hour.from_now, last_seen_at: Time.current,
  verified_at: Time.current, grant_token: "rollback-fixture")
jar = ActionDispatch::TestRequest.create.cookie_jar
jar.signed[:session_id] = session.id
browser = ActionDispatch::Integration::Session.new(Rails.application)
browser.cookies[:session_id] = jar[:session_id]
def page(browser, path)
  browser.get(path)
  raise "Request #{path} returned #{browser.response.status}: #{browser.response.body.first(200)}" unless browser.response.ok?
  Nokogiri::HTML(browser.response.body)
end
def assert(condition, explanation)
  raise explanation unless condition
  puts "PASS #{explanation}"
end

def protected_state
  tables = %w[artists releases recordings catalog_track_slots release_artists recording_artists resolution_decisions
    catalog_revisions catalog_imports musical_identity_decisions scrobbles]
  connection = ActiveRecord::Base.connection
  tables.to_h do |table|
    quoted_table = connection.quote_table_name(table)
    rows = connection.select_values("SELECT to_jsonb(rows)::text FROM #{quoted_table} rows ORDER BY id")
    [ table, Digest::SHA256.hexdigest(rows.join("\n")) ]
  end
end

before = protected_state
migration_versions = ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations ORDER BY version")
assert(migration_versions.include?("20261122170100"), "v0.6.0 edition-slot migration is present")
doc = page(browser, "/releases/#{release_id}")
assert(doc.css(".release-tracks tbody tr").size == 13, "Guilt Show has 13 base tracks")
assert(doc.at_css(".music-sheet").text.include?("2004-03-02"), "Original date is March 2")
assert(!doc.at_css(".release-tracks").text.include?(recording.title), "Japanese track is outside base sequence")
additions = doc.at_css("#additional-edition-appearances")
assert(additions.text.include?(recording.title) && additions.text.include?("2004-08-21") &&
  additions.text.include?("track 14"), "Japanese additional track and August 21 date survive rollback")
assert(doc.at_css("#listening-activity").text.include?("3 distinct resolved observations"), "Multiple appearances count just three observations")
recording_page = page(browser, "/recordings/#{recording_id}")
assert(recording_page.at_css("#recording-chronology").text.include?("2003 to 2004-01"), "Independent recording range survives rollback")
assert(recording_page.at_css("#recording-chronology").text.include?("2004-06-22"), "First release remains June 22")
assert(recording_page.css("a").any? { |link| link["href"] == "/releases/#{release_id}" }, "Bonus recording retains Guilt Show membership")
combined = page(browser, "/releases/#{release_id}?with_release[]=#{overlap_id}")
assert(combined.at_css("#listening-activity").text.include?("3 distinct resolved observations"), "Overlapping release histories deduplicate observations")
tracklist = RecordingResolution::ReleaseTracklist.new(release)
assert(tracklist.slots.size == 13, "Resolution evidence uses 13 base tracks")
assert(tracklist.evidence["edition_mbid"] == "bb53ef0f-8e06-4cb1-b0ef-7ef2188e2750", "Reviewed US evidence wins over the historic Japanese edition identifier")
assert(protected_state == before, "Catalog, source observations, evidence, assignments and revision rows are byte-for-byte unchanged")
assert(ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations ORDER BY version") == migration_versions,
  "No schema migration was reversed")
