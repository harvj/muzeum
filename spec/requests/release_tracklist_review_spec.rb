require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/archive_scale"

RSpec.describe "Release tracklist review", type: :request do
  include OidcFlow
  include ArchiveScale

  before do
    prepare_oidc
    finish_oidc
    @listener = User.find_by!(oidc_subject: @subject)
    @account = LastfmAccount.associate!(@listener, "batch-fixture")
    @artist = Artist.create!(name: "Fixture artist", mbid: SecureRandom.uuid)
    @release = Release.create!(title: "Fixture album", ingested_from_release_mbid: SecureRandom.uuid, catalog_verified_at: Time.current)
    @anchor, @accepted, @rejected = %w[Anchor Candidate Alternate].each_with_index.map do |title, i|
      recording = Recording.create!(title:, mbid: SecureRandom.uuid)
      RecordingArtist.create!(artist: @artist, recording:, position: 0)
      CatalogTrackSlot.create!(release: @release, recording:, medium: 1, position: i + 1, track_mbid: SecureRandom.uuid, title:)
      observation(title, recording)
    end
    @anchor_recording = @release.catalog_track_slots.first.recording
    RecordingResolution::Ledger.record!(listener: @listener, scrobble: @anchor, scope: :scrobble, mode: "resolved",
      reason: "Confirmed recording", recording: @anchor_recording)
    record_tracklist
  end

  after { restore_oidc }

  def observation(title, recording = nil)
    @listener.scrobbles.create!(lastfm_account: @account, played_at: Time.current, payload: {
      artist_name: @artist.name, album_name: @release.title, track_name: title, album_mbid: @release.ingested_from_release_mbid,
      track_mbid: recording&.mbid
    }.compact)
  end

  def record_tracklist
    slots = @release.catalog_track_slots.order(:medium, :position).includes(:recording)
    digest = Digest::SHA256.hexdigest(slots.map { |slot| [ slot.medium, slot.position, slot.recording.mbid ] }.to_json)
    CatalogRevision.create!(entity_type: "Release", entity_id: @release.id,
      catalog_import: CatalogImport.request!("recording", @anchor_recording.id),
      evidence: { edition_mbid: @release.ingested_from_release_mbid, track_count: slots.size, tracklist_digest: digest, requests: [] })
  end

  def open_batch
    get release_batch_resolution_surface_path(@anchor, release_id: @release.id)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def submit(token, choices)
    post confirm_release_batch_resolution_surface_path(@anchor, release_id: @release.id),
      params: { batch_token: token, choices: }
  end

  it "groups scoped plays at scale and records accepted and explicitly rejected choices without changing observations" do
    seed_archive_at_scale(@listener)
    Release.connection.execute("INSERT INTO releases (title) SELECT 'Unrelated edition ' || n FROM generate_series(1, 10000) AS n")
    observation("Anchor", @anchor_recording)
    repeated = observation("Candidate", @release.catalog_track_slots.find_by!(position: 2).recording)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    doc = open_batch
    if ENV["MEASURE_RELEASE_BATCH"] == "1"
      warn "293,000+ observations / 10,000+ releases batch: #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)} ms"
    end
    legends = doc.css("legend").map(&:text)
    expect(legends).to include("Candidate · 2 observations", "Alternate · 1 observation")
    expect(legends.grep(/Anchor/)).to be_empty
    expect(doc.text).to include("independently confirmed in your archive", "Track 2")
    token = doc.at_css('[name="batch_token"]')["value"]
    choices = legends.each_with_index.to_h { |label, i| [ i.to_s, label.start_with?("Candidate") ? "accept" : "reject" ] }
    expect { submit(token, choices) }.to change(RecordingResolution::Decision, :count).by(3)
    expect(response).to have_http_status(:see_other)
    decisions = RecordingResolution::Decision.where(scrobble_id: [ @accepted.id, repeated.id, @rejected.id ]).index_by(&:scrobble_id)
    expect(decisions.fetch(@accepted.id).evidence.dig("review_snapshot", "affected_observation_ids")).to match_array([ @accepted.id, repeated.id ])
    expect(decisions.fetch(@rejected.id).evidence.dig("review_snapshot", "feedback")).to eq("rejected")
    expect(decisions.fetch(@rejected.id).mode).to eq("inherit")
    expect(Scrobble.find(@accepted.id).payload).to eq(@accepted.payload)
    expect { submit(token, choices) }.not_to change(RecordingResolution::Decision, :count)
  end

  it "refuses an incomplete stored edition and does not overwrite a decision after showing the batch" do
    doc = open_batch
    token = doc.at_css('[name="batch_token"]')["value"]
    index = doc.css("legend").map(&:text).index { |label| label.start_with?("Candidate") }
    RecordingResolution::Ledger.record!(listener: @listener, scrobble: @accepted, scope: :scrobble, mode: "resolved",
      reason: "Another decision", recording: @anchor_recording)
    expect { submit(token, index.to_s => "accept") }.not_to change(RecordingResolution::Decision, :count)
    @release.catalog_track_slots.last.destroy!
    get release_batch_resolution_surface_path(@anchor, release_id: @release.id)
    expect(response).to redirect_to(resolution_surface_path(@anchor))
  end

  it "keeps duplicate tracks and conflicting editions out of batch acceptance" do
    competing = Recording.create!(title: "Candidate", mbid: SecureRandom.uuid)
    RecordingArtist.create!(recording: competing, artist: @artist, position: 0)
    CatalogTrackSlot.create!(release: @release, recording: competing, medium: 2, position: 1,
      track_mbid: SecureRandom.uuid, title: "Candidate")
    record_tracklist
    without_id = observation("Candidate")
    other_edition = Release.create!(title: @release.title, ingested_from_release_mbid: SecureRandom.uuid, catalog_verified_at: Time.current)
    CatalogTrackSlot.create!(release: other_edition, recording: competing, medium: 1, position: 2,
      track_mbid: SecureRandom.uuid, title: "Candidate")
    @listener.scrobbles.create!(lastfm_account: @account, played_at: Time.current,
      payload: without_id.payload.merge("album_mbid" => other_edition.ingested_from_release_mbid))
    doc = open_batch
    ambiguous = doc.css("fieldset").find { |field| field.text.include?("competing version") }
    expect(ambiguous.text).to include("Track 2", "Track 4")
    expect(ambiguous.css('option[value="accept"]')).to be_empty
    expect(doc.css("legend").map(&:text).grep(/Candidate/)).to all(include("1 observation"))
  end

  it "uses stored evidence without a provider lookup and signs listener-only corroboration" do
    target = observation("Candidate")
    surface = RecordingResolution::Ledger.attach!(target)
    claims = target.payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims:)
    request = CatalogImport.request!("recording_investigation", group.id,
      "observation_id" => target.id, "requester_id" => @listener.id)
    session = double("local only", provenance: [])
    expect(session).not_to receive(:get)
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { session }).call
    assessment = RecordingResolution::Ledger.assessments(@listener).sole
    expect(assessment.evidence.fetch("ranking").first.fetch("inputs")).not_to have_key("local_release_history")
    expect(assessment.evidence.dig("edition", "complete_tracklist")).to be(true)

    get resolution_surface_path(target, play: target.id, section: "evidence")
    doc = Nokogiri::HTML(response.body)
    expect(doc.text).to include("another recording independently confirmed in your archive")
    token = doc.at_css('[name="listener_ranking_token"]')["value"]
    post decide_resolution_surface_path(target), params: { scope: "scrobble", play_id: target.id, mode: "resolved",
      assessment_id: assessment.id, recording_mbid: @accepted.payload["track_mbid"], listener_ranking_token: token }
    decision = RecordingResolution::Decision.where(scrobble_id: target.id).sole
    expect(decision.evidence.dig("review_snapshot", "ranking", 0, "inputs", "local_release_history", "provenance"))
      .to include("independent_decision_id" => RecordingResolution::Decision.find_by!(scrobble_id: @anchor.id).id)
  end
end
