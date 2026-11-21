require "rails_helper"
require "tmpdir"
require_relative "../support/oidc_flow"
require_relative "../support/archive_scale"

RSpec.describe "Listening archive", type: :request do
  include OidcFlow
  include ArchiveScale
  before { prepare_oidc; finish_oidc }
  after { restore_oidc }

  it "associates only the authenticated user after public username validation" do
    stub_request(:get, /ws.audioscrobbler.com/).to_return(body: '<lfm status="ok"><user><name>Listener</name></user></lfm>')
    stub_const("ENV", ENV.to_h.merge("LASTFM_API_KEY" => "test-key"))
    patch lastfm_account_path, params: { lastfm_username: "Listener", user_id: 999 }
    expect(User.find_by!(oidc_subject: @subject).lastfm_username).to eq("Listener")
    post imports_path
    run = ImportRun.last
    expect(run.source_username).to eq("Listener")
    expect(run.upper_bound).to be_present
    expect { post imports_path }.not_to change(ImportRun, :count)
  end

  it "handles invalid names and upstream outages without changing the association" do
    patch lastfm_account_path, params: { lastfm_username: "../bad" }
    expect(User.last.lastfm_username).to be_nil
    stub_const("ENV", ENV.to_h.merge("LASTFM_API_KEY" => "test-key"))
    stub_request(:get, /ws.audioscrobbler.com/).to_return(status: 503)
    patch lastfm_account_path, params: { lastfm_username: "someone" }
    expect(User.last.lastfm_username).to be_nil
  end

  it "recognizes delayed publication on the next request and hides a mismatched tag" do
    Dir.mktmpdir do |directory|
      path = Pathname(directory).join("PUBLISHED_RELEASE")
      sha = "a" * 40
      allow(Rails.configuration.x).to receive(:published_release_path).and_return(path)
      allow(Rails.configuration.x).to receive(:running_revision).and_return(sha)

      get archive_path
      expect(Nokogiri::HTML(response.body).at_css(".site-footer").text).not_to include("Muzeum v")

      path.write("#{sha} v0.2.1\n")
      get archive_path
      expect(Nokogiri::HTML(response.body).at_css(".site-footer").text).to include("Muzeum v0.2.1")

      path.write("#{'b' * 40} v0.2.2\n")
      get archive_path
      expect(Nokogiri::HTML(response.body).at_css(".site-footer").text).not_to include("Muzeum v")
    end
  end

  it "uses the packaged version only for the running revision before publication" do
    Dir.mktmpdir do |directory|
      reviewed = Pathname(directory).join("REVIEWED_RELEASE")
      sha = "a" * 40
      allow(Rails.configuration.x).to receive(:reviewed_release_path).and_return(reviewed)
      allow(Rails.configuration.x).to receive(:running_revision).and_return(sha)
      reviewed.write("#{sha} v0.3.4\n")
      get archive_path
      expect(response.body).to include("Muzeum v0.3.4")
      allow(Rails.configuration.x).to receive(:running_revision).and_return("b" * 40)
      get archive_path
      expect(response.body).not_to include("Muzeum v0.3.4")
    end
  end

  it "computes statistics from only the user's persisted observations" do
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "stats-fixture")
    user.scrobbles.create!(played_at: Time.utc(2020), payload: { artist_name: "Artist", album_name: "Album", track_name: "Track" })
    user.scrobbles.create!(played_at: Time.utc(2021), payload: { artist_name: "Artist", album_name: "", track_name: "Other" })
    other = User.create!(lastfm_username: "other")
    other.scrobbles.create!(played_at: Time.utc(1999), payload: { artist_name: "Private Artist" })
    get archive_summary_path
    expect(response.body).to include("01 Jan 2020", "01 Jan 2021", "Observed artists", "Observed albums", "Observed tracks")
    expect(response.body).not_to include("1999", "Private Artist", "User management")
    expect(response.body).to include("harvj-session")
    expect(controller.instance_variable_get(:@artists)).to eq(1)
    expect(controller.instance_variable_get(:@albums)).to eq(1)
    expect(controller.instance_variable_get(:@tracks)).to eq(2)
  end

  it "reuses source statistics until an observation is appended, without caching archive access" do
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "summary-cache-fixture")
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    user.scrobbles.create!(played_at: Time.utc(2021), payload: { artist_name: "", album_name: "Album", track_name: "Track" })
    reads = []
    listener = ->(event) { reads << event.payload[:sql] if event.payload[:sql].include?("GROUPING SETS") }
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
      2.times { get archive_summary_path }
      expect(reads.size).to eq(1)
      user.scrobbles.create!(played_at: Time.utc(2020), payload: { album_name: "Album", track_name: "Track" })
      get archive_summary_path
      expect(reads.size).to eq(2)
      expect(controller.instance_variable_get(:@albums)).to eq(2)
      expect(controller.instance_variable_get(:@artists)).to eq(0)
      expect(response.body).to include("01 Jan 2020")
      user.user_lastfm_accounts.active.sole.revoke!
      get archive_summary_path
      expect(reads.size).to eq(2)
      expect(controller.instance_variable_get(:@count)).to eq(0)
    end
  end

  it "bounds each page and dashboard refresh even with a production-sized archive" do
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "archive-scale")
    seed_archive_at_scale(user)
    expect(user.archive_observations.count).to eq(ArchiveScale::SIZE)
    expected = user.archive_observations.order(played_at: :desc, id: :desc).limit(100).ids
    expect(Scrobble.find(expected[49]).played_at).to eq(Scrobble.find(expected[50]).played_at)
    statements = []
    capture = ->(event) { statements << event.payload.fetch(:sql) if event.payload.fetch(:sql).include?('"scrobbles"') }

    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") do
      get archive_path
      first = Nokogiri::HTML(response.body)
      expect(first.at_css('a[data-turbo-prefetch="false"]')["href"]).to eq(archive_summary_path)
      expect(first.css(".play-row th a").map { |link| link["href"] }).to eq(expected.first(50).map { |id| resolution_surface_path(id) })
      older = first.at_xpath('//a[text()="Older plays"]')["href"]
      get older
      second = Nokogiri::HTML(response.body)
      expect(second.css(".play-row th a").map { |link| link["href"] }).to eq(expected.last(50).map { |id| resolution_surface_path(id) })
      expect(second.at_css("#archive_dashboard")["data-dashboard-sync-version-value"]).to eq("")
      get dashboard_updates_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
    end

    reads = statements.grep(/SELECT .*FROM (?:"scrobbles"|jsonb_to_recordset)/)
    expect(reads.size).to eq(7)
    expect(reads.grep(/FROM jsonb_to_recordset.* JOIN .*resolution_grant/).size).to eq(3)
    expect(reads.grep(/ORDER BY "scrobbles"."played_at" DESC, "scrobbles"."id" DESC LIMIT/).size).to eq(3)
    expect(reads).not_to include(a_string_matching(/COUNT\(|SELECT DISTINCT |OFFSET /i))

    target = Recording.create!(title: "Scoped recording", mbid: SecureRandom.uuid)
    unrelated = Recording.create!(title: "Protected exception", mbid: SecureRandom.uuid)
    play = user.scrobbles.find(expected.first)
    RecordingResolution::Ledger.record!(listener: user, scrobble: play, scope: :surface, mode: "resolved", reason: "Test", recording: target)
    inherited = user.scrobbles.create!(played_at: 1.day.ago, payload: play.payload)
    RecordingResolution::Ledger.record!(listener: user, scrobble: play, scope: :scrobble, mode: "resolved", reason: "Test", recording: unrelated)
    expect(RecordingResolution::Ledger.for_recordings(user, target.id).ids).to eq([ inherited.id ])
    expect(RecordingResolution::Ledger.for_recordings(user, unrelated.id).ids).to eq([ play.id ])
    user.user_lastfm_accounts.active.sole.revoke!
    expect(RecordingResolution::Ledger.for_recordings(user, target.id)).to be_empty
  end

  it "rejects another account's cursor on the private Archive" do
    other = User.create!(lastfm_username: "other-archive-cursor")
    observation = other.scrobbles.create!(played_at: Time.current, payload: {})
    LastfmAccount.associate!(User.find_by!(oidc_subject: @subject), "reader-archive")
    get archive_path(before: observation.id)
    expect(response).to have_http_status(:not_found)
    get archive_path(before: [ observation.id ])
    expect(response).to have_http_status(:not_found)
  end
end
