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
    expect(evidence.dig("discogs", "incomplete_reasons")).to eq([ "provider_unconfigured" ])
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
  [ true, false ].each do |recovers|
    it "keeps MusicBrainz evidence when Discogs HTTP 500 #{recovers ? 'recovers' : 'exhausts retries'}" do
      freeze_time do
        observation = catalog_observation(listener)
        surface = RecordingResolution::Ledger.attach!(observation)
        request = CatalogImport.request!("assessment", surface.id, "observation_id" => observation.id, "requester_id" => listener.id)
        env = { "DISCOGS_CONSUMER_KEY" => "FixtureKey", "DISCOGS_CONSUMER_SECRET" => "FixtureSecret" }
        allow(ENV).to receive(:values_at).and_call_original
        allow(ENV).to receive(:values_at).with(*env.keys).and_return(env.values)

        discogs_calls = 0
        factory = lambda do |row, token|
          transport = RecordingResolution::ProviderSession.new(row, token, catalog: true)
          allow(transport).to receive(:fetch).and_wrap_original do |_, provider, path, params, _headers|
            if provider == :discogs
              expect(path).to eq("/database/search")
              discogs_calls += 1
              if recovers && discogs_calls > 1
                [ 200, {}, { pagination: { page: 1, pages: 0, items: 0, per_page: 25 }, results: [] }.to_json ]
              else
                [ 500, { "Retry-After" => "20" }, "discarded provider response" ]
              end
            else
              [ 200, {}, session.get(provider, path, params:).fetch("data").to_json ]
            end
          end
          transport
        end

        run = lambda do
          described_class.new(request, session_factory: factory).call
          request.reload
        end
        expect do
          20.times do
            run.call
            break if request.attempts.positive?

            travel_to request.due_at
          end
          expect(request).to have_attributes(state: "pending", attempts: 1, due_at: 20.seconds.from_now)
          expect(RecordingResolution::ProviderBudget.find_by!(provider: "discogs").available_at).to eq(request.due_at)
          partial = RecordingResolution::Ledger.assessments(listener).sole.evidence
          expect(partial).to include("partial" => true)
          expect(partial.fetch("candidates")).not_to be_empty
          expect(partial.dig("reason_details", "provider_temporarily_unavailable")).to include(
            "provider" => "discogs", "endpoint" => "/database/search", "http_status" => 500)
          expect(partial.to_json).not_to include("FixtureSecret", "discarded provider response")

          10.times do
            travel_to request.due_at
            run.call
            break unless request.active?
          end
        end.not_to change(RecordingResolution::Decision, :count)

        expect(request.state).to eq(recovers ? "imported" : "failed")
        expect(discogs_calls).to eq(recovers ? 2 : 5)
        expect(RecordingResolution::Ledger.assessments(listener).order(:id).last.evidence["partial"]).to eq(recovers ? nil : true)
      end
    end
  end
end
