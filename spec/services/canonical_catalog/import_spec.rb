require "rails_helper"
require_relative "../../support/catalog_fixtures"

RSpec.describe CanonicalCatalog::Processor do
  include CatalogFixtures
  include ActiveSupport::Testing::TimeHelpers

  let(:session) { CatalogFixtures::Session.new }
  let(:listener) { User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "catalog-listener", lastfm_username: "catalog-source") }
  let(:recording) { Recording.create!(mbid: CatalogFixtures::IDS[:studio], title: "Signals") }

  def process(request)
    described_class.new(request, session_factory: ->(*) { session }).call
    request.reload
  end

  it "reuses and creates the complete ordered Influence credit on repeated verified imports" do
    edition = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/releases/lady_wood_vinyl.json").read)
    data = edition.fetch("media").flat_map { |medium| medium.fetch("tracks") }
      .find { |track| track["title"] == "Influence" }.fetch("recording")
    tove_data, wiz_data = data.fetch("artist-credit").map { |credit| credit.fetch("artist") }
    tove = Artist.create!(mbid: tove_data.fetch("id"), name: tove_data.fetch("name"))
    entry = CanonicalCatalog::Store.recording!(data)
    request = CatalogImport.request!("recording", entry.id)

    expect do
      CanonicalCatalog::Store.new(request, session).recording(data)
    end.to change(Artist, :count).by(1).and change(RecordingArtist, :count).by(2)
    wiz = Artist.find_by!(mbid: wiz_data.fetch("id"))
    expect(entry.recording_artists.order(:position).pluck(:artist_id)).to eq([ tove.id, wiz.id ])
    expect(CatalogRevision.find_by!(entity_type: "Recording", entity_id: entry.id).evidence.fetch("artist_credit"))
      .to eq([
        { "artist_mbid" => tove.mbid, "credited_name" => "Tove Lo", "join_phrase" => " feat. " },
        { "artist_mbid" => wiz.mbid, "credited_name" => "Wiz Khalifa", "join_phrase" => "" }
      ])
    request.update!(state: "imported")
    refresh = CatalogImport.request!("recording", entry.id)
    expect do
      CanonicalCatalog::Store.new(refresh, session).recording(data)
    end.not_to change { [ Artist.count, Recording.count, RecordingArtist.count ] }
    alias_evidence = data.deep_dup
    alias_evidence["artist-credit"].last["name"] = "Wiz"
    refresh.update!(state: "imported")
    alias_request = CatalogImport.request!("recording", entry.id)
    CanonicalCatalog::Store.new(alias_request, session).recording(alias_evidence)
    surface = RecordingResolution::RealCorpusEvaluation::Observation.new(artist: "Wiz", album: "Lady Wood", track: "Influence")
    expect(RecordingResolution::LocalCandidates.catalog_identity(surface)).to include(artist_mbid: wiz.mbid)
    ranking = RecordingResolution::Ranking.call(surface, { "candidates" => [ data ],
      "canonical_artist_mbid" => wiz.mbid }, source_hints: true)
    expect(ranking.first.dig("inputs", "artist_name", "state")).to eq("positive")
    [ tove, wiz ].each do |artist|
      surface = RecordingResolution::RealCorpusEvaluation::Observation.new(artist: artist.name, album: "Lady Wood", track: "Influence")
      expect(RecordingResolution::LocalCandidates.catalog_identity(surface)).to include(artist_mbid: artist.mbid, recording_mbid: entry.mbid)
    end
  end

  it "admits one contextual edition with a complete multi-disc listing and no new plays" do
    observation = catalog_observation(listener)
    original = observation.attributes
    decision = RecordingResolution::Ledger.record!(listener:, scrobble: observation, scope: :surface, mode: "resolved",
      recording:, reason: "Confirmed studio recording")
    request = CatalogImport.request!("recording", recording.id, "album" => "Night Drive", "observed_edition_mbid" => CatalogFixtures::IDS[:edition])

    expect { process(request) }.not_to change(Scrobble, :count)
    expect(request.state).to eq("imported")
    release = Release.find_by!(ingested_from_release_mbid: CatalogFixtures::IDS[:edition])
    expect(release.catalog_track_slots.order(:medium, :position).pluck(:medium, :position, :title)).to eq(
      [ [ 1, 1, "Signals" ], [ 1, 2, "Different Song" ], [ 2, 1, "Signals" ] ])
    expect(Release.count).to eq(1)
    expect(Recording.count).to eq(2)
    expect(Artist.count).to eq(1)
    expect(session.paths.grep(%r{/release/}).size).to eq(1)
    expect(observation.reload.attributes).to eq(original)
    expect(RecordingResolution::Decision.sole).to eq(decision)
    expect(RecordingResolution::Ledger.effective(listener).find(observation.id).effective_recording_id).to eq(recording.id)

    refresh = CatalogImport.request!("release", release.id)
    expect { process(refresh) }.not_to change(CatalogTrackSlot, :count)
    expect(refresh.state).to eq("imported")
    expect(Release.count).to eq(1)
  end

  it "keeps the decision and recording if release evidence is incomplete, and admits a deliberate eligible choice later" do
    observation = catalog_observation(listener)
    decision = RecordingResolution::Ledger.record!(listener:, scrobble: observation, scope: :scrobble, mode: "resolved",
      recording:, reason: "Confirmed recording")
    request = CatalogImport.request!("recording", recording.id, "album" => "Something else")
    expect(process(request).state).to eq("incomplete")
    expect(Release.count).to eq(0)
    expect(recording.reload.artists.pluck(:name)).to eq([ "Night Lines" ])
    expect(RecordingResolution::Decision.sole).to eq(decision)
    explicit = CatalogImport.request!("recording", recording.id, "edition_mbid" => CatalogFixtures::IDS[:edition])
    expect(process(explicit).state).to eq("imported")
    expect(Release.count).to eq(1)
  end

  it "refreshes previously verified metadata and preserves missing fields and separately corrected values" do
    artist = Artist.create!(mbid: CatalogFixtures::IDS[:artist], name: "Night Lines")
    first = CatalogImport.request!("artist", artist.id)
    expect(CatalogImport.request!("artist", artist.id)).to eq(first)
    process(first)
    artist.update!(name: "Reviewed spelling")
    session.artist_data = session.artist_data.merge("country" => nil, "name" => "New provider spelling")
    process(CatalogImport.request!("artist", artist.id))

    expect(artist.reload.attributes.values_at("name", "country")).to eq([ "Reviewed spelling", "US" ])
    expect(CatalogRevision.order(:id).last.evidence["conflicts"]).to eq("name" => [ "Reviewed spelling", "New provider spelling" ])
    session.artist_data = session.artist_data.merge("country" => "GB")
    process(CatalogImport.request!("artist", artist.id))
    expect(artist.reload.country).to eq("GB")
    expect(CatalogRevision.order(:id).last.evidence["changes"]).to eq("country" => [ "US", "GB" ])
  end

  it "does not admit a contextual compilation unless a listener deliberately selects it" do
    edition = session.edition
    edition.fetch("release-group")["secondary-types"] = [ "Compilation" ]
    allow(session).to receive(:edition).and_return(edition)
    context = { "album" => "Night Drive", "observed_edition_mbid" => CatalogFixtures::IDS[:edition] }
    expect(process(CatalogImport.request!("recording", recording.id, context)).state).to eq("incomplete")
    expect(Release.count).to eq(0)

    context["edition_mbid"] = CatalogFixtures::IDS[:edition]
    expect(process(CatalogImport.request!("recording", recording.id, context)).state).to eq("imported")
    expect(Release.sole).to be_compilation
  end

  it "checks provider evidence for one authorized observation without assigning a recording" do
    observation = catalog_observation(listener)
    surface = RecordingResolution::Ledger.attach!(observation)
    request = CatalogImport.request!("assessment", surface.id, "observation_id" => observation.id, "requester_id" => listener.id)

    expect { process(request) }.not_to change(RecordingResolution::Decision, :count)
    expect(request.state).to eq("imported")
    evidence = RecordingResolution::Ledger.assessments(listener).sole.evidence
    expect(evidence).to include("review_mbid" => CatalogFixtures::IDS[:studio])
    expect(evidence).not_to have_key("discogs")
    expect(Release.count).to eq(0)

    next_request = CatalogImport.request!("assessment", surface.id, request.context)
    listener.user_lastfm_accounts.active.sole.revoke!
    session.paths.clear
    expect(process(next_request).state).to eq("incomplete")
    expect(session.paths).to be_empty
  end

  it "retries a transient provider failure without changing the protected decision" do
    freeze_time do
      observation = catalog_observation(listener)
      decision = RecordingResolution::Ledger.record!(listener:, scrobble: observation, scope: :surface, mode: "resolved",
        recording:, reason: "Confirmed recording")
      request = CatalogImport.request!("recording", recording.id, "album" => "Night Drive")
      allow(session).to receive(:get).and_wrap_original do |original, provider, path, **options|
        if path.start_with?("/ws/2/release/") && request.attempts.zero?
          raise RecordingResolution::ProviderError.new("musicbrainz throttled", retry_at: 20.seconds.from_now)
        end

        original.call(provider, path, **options)
      end
      expect(process(request)).to have_attributes(state: "pending", attempts: 1, due_at: 20.seconds.from_now)
      expect(recording.reload.artists.count).to eq(1)
      expect(Release.count).to eq(0)
      expect(RecordingResolution::Decision.sole).to eq(decision)
      travel 20.seconds
      expect(process(request).state).to eq("imported")
    end
  end
  it "uses only MusicBrainz for new investigations with Discogs credentials configured" do
    observation = catalog_observation(listener)
    request = RecordingResolution::Investigation.new(listener, observation).request
    allow(ENV).to receive(:values_at).and_call_original
    allow(ENV).to receive(:values_at).with("DISCOGS_CONSUMER_KEY", "DISCOGS_CONSUMER_SECRET")
      .and_return([ "FixtureKey", "FixtureSecret" ])
    allow(session).to receive(:get).and_call_original
    expect(session).not_to receive(:get).with(:discogs, any_args)

    expect { expect(process(request).state).to eq("imported") }.not_to change(RecordingResolution::Decision, :count)
    evidence = RecordingResolution::Ledger.assessments(listener).sole.evidence
    expect(evidence.fetch("ranking").first).to include("recording_mbid" => CatalogFixtures::IDS[:studio], "version" => RecordingResolution::Ranking::SOURCE_HINTS_VERSION)
    expect(session.provenance.pluck("provider").uniq).to eq([ "musicbrainz" ])
  end
end
