require "rails_helper"

RSpec.describe "Recording resolution HTTP contracts" do
  include ActiveSupport::Testing::TimeHelpers

  let(:ids) { RecordingResolution::FixtureTransport::IDS }
  let(:listener) { User.create!(lastfm_username: "contract_archive", oidc_issuer: OidcClient::ISSUER, oidc_subject: "contract") }
  let(:archive) { listener.source_account }

  def stub_catalog(provider, path, params, fixture)
    host = RecordingResolution::ProviderSession::ORIGINS.fetch(provider)
    request = stub_request(:get, "#{host}#{path}").with(query: params, headers: { "User-Agent" => /Muzeum/ })
    request.with(headers: { "Authorization" => "Discogs key=FixtureKey, secret=FixtureSecret" }) if provider == :discogs
    status, headers, body = fixture.call(provider, path, params)
    request.to_return(status:, headers:, body:)
  end

  it "runs the official HTTP endpoints and persists independent budget deferrals between requests" do
    allow(ENV).to receive(:values_at).and_call_original
    allow(ENV).to receive(:values_at).with("DISCOGS_CONSUMER_KEY", "DISCOGS_CONSUMER_SECRET")
      .and_return([ "FixtureKey", "FixtureSecret" ])

    fixture = RecordingResolution::FixtureTransport.new
    search = stub_catalog(:musicbrainz, "/ws/2/recording", {
      query: 'artist:"Night Lines" AND recording:"Signals"', limit: 25, offset: 0, fmt: "json"
    }, fixture)
    lookup = stub_catalog(:musicbrainz, "/ws/2/recording/#{ids[:studio]}", {
      fmt: "json", inc: "artist-credits+releases+release-groups+isrcs"
    }, fixture)
    edition = stub_catalog(:musicbrainz, "/ws/2/release/#{ids[:edition]}", {
      fmt: "json", inc: "recordings+artist-credits+release-groups"
    }, fixture)
    discogs_search = stub_catalog(:discogs, "/database/search", {
      type: "release", artist: "Night Lines", release_title: "Night Drive", page: 1, per_page: 25
    }, fixture)
    discogs_edition = stub_catalog(:discogs, "/releases/123", {}, fixture)

    freeze_time do
      observation = Scrobble.create!(user: listener, lastfm_account: archive, played_at: Time.current,
        source_fingerprint: SecureRandom.hex(32),
        payload: { artist_name: "Night Lines", album_name: "Night Drive", track_name: "Signals", track_mbid: ids[:studio] })
      pilot = RecordingResolution::PilotRunner.start!(archive_id: archive.id, upper_id: observation.id, live: true)
      RecordingResolution::PilotRunner.select!(pilot)
      work = RecordingResolution::Work.find_by!(pilot_id: pilot.id)
      processor = RecordingResolution::Processor.new(work)
      processor.call
      expect(work.reload).to have_attributes(state: "pending", attempts: 0, due_at: 1.second.from_now)
      travel 1.second
      processor.call
      expect(work.reload.due_at).to eq(1.second.from_now)
      travel 1.second
      processor.call
      expect(work.reload).to have_attributes(state: "pending", due_at: 3.seconds.from_now)
      travel 3.seconds
      processor.call
      expect(work.reload.state).to eq("done")
      [ search, lookup, edition, discogs_search, discogs_edition ].each do |request|
        expect(request).to have_been_requested.once
      end
      assessment = RecordingResolution::Assessment.find(work.assessment_id)
      expect(assessment.evidence.dig("discogs", "status")).to eq("corroborates")
      expect(assessment.evidence.to_json).not_to include("FixtureSecret", '"tracklist"')
    end
  end

  it "projects Discogs catalog results without retaining images, seller data, or pagination URLs" do
    session = instance_double(RecordingResolution::ProviderSession)
    expect(session).to receive(:get).with(:discogs, "/masters/12/versions",
      params: { page: 2, per_page: 25 }, headers: {}) do |*, &project|
      { "data" => project.call({
        "pagination" => { "page" => 2, "pages" => 3, "urls" => { "next" => "ignored" } },
        "versions" => [ { "id" => 123, "title" => "Night Drive", "country" => "US", "released" => "2020",
          "thumb" => "ignored", "stats" => { "community" => {} } } ]
      }) }
    end
    response = Clients::Discogs.new(session, live: false).versions(12, page: 2)
    expect(response).to eq("pagination" => { "page" => 2, "pages" => 3 },
      "versions" => [ { "id" => 123, "title" => "Night Drive", "country" => "US", "released" => "2020" } ])
  end
end
