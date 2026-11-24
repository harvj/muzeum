require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/catalog_fixtures"
require_relative "../support/discovery_replay"
require_relative "../support/guilt_show_fixture"
require_relative "../support/narrow_stairs_fixture"

RSpec.describe "Canonical library and resolution workspace", type: :request do
  include OidcFlow
  include CatalogFixtures
  include GuiltShowFixture
  include NarrowStairsFixture
  before { prepare_oidc }
  after { restore_oidc }

  it "requires a specific retained edition when two complete original sequences conflict" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "original-tracklist-conflict")
    observation, assessment = narrow_stairs_assessment(user)
    original = narrow_stairs_editions.find { |edition| edition["id"] == NarrowStairsFixture::ORIGINAL }
    other = original.deep_dup.merge("id" => SecureRandom.uuid)
    tracks = other.dig("media", 0, "tracks")
    tracks[0], tracks[1] = tracks[1], tracks[0]
    tracks.first(2).each_with_index { |track, index| track.merge!("position" => index + 1, "number" => (index + 1).to_s) }
    assessment = RecordingResolution::Assessment.create!(group_id: assessment.group_id, version: assessment.version, actor: assessment.actor,
      digest: SecureRandom.hex(32), evidence: assessment.evidence.merge("construction_editions" => [ original, other ]))

    get resolution_surface_path(observation)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css('input[type="radio"][name="construct_release"]').map { |option| option["value"] }).to contain_exactly(original["id"], other["id"])
    params = { scope: "surface", recording_mbid: NarrowStairsFixture::RECORDING, assessment_id: assessment.id }
    post decide_resolution_surface_path(observation), params: params.merge(construct_release: NarrowStairsFixture::GROUP)
    expect(RecordingResolution::Decision.count).to eq(0)

    post decide_resolution_surface_path(observation), params: params.merge(construct_release: other["id"])
    expect(flash[:notice]).to eq("Recording decision saved.")
    release = Release.sole
    expect(release.ingested_from_release_mbid).to eq(other["id"])
    expect(release.catalog_track_slots.base_sequence.order(:medium, :position).pluck(:title)).to eq(tracks.pluck("title"))
    expect(release.catalog_track_slots.additional_appearances).to be_empty

    # Existing v0.6.0 selections are identified by their reviewed import, without a new flag.
    source = Struct.new(:provenance).new([])
    chosen_slots = CanonicalCatalog::Edition.new(other, other.fetch("id")).slots
    background = CatalogImport.create!(kind: "release", entity_id: release.id, due_at: Time.current, state: "imported")
    expect do
      CanonicalCatalog::Store.new(background, source).release(original, chosen_slots, strict_collection: true)
    end.to raise_error(CanonicalCatalog::Store::Unverified, /reviewed original release/)
    expect(RecordingResolution::ReleaseTracklist.new(release.reload).evidence["edition_mbid"]).to eq(other["id"])
  end

  it "shows a prior single separately from the album and confirms one original collection" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "earlier-single-context")
    observation, assessment = narrow_stairs_assessment(user, publication: true)
    original = narrow_stairs_editions.find { |edition| edition["id"] == NarrowStairsFixture::ORIGINAL }
    track = original.dig("media", 0, "tracks", 2).merge("position" => 1, "number" => "1")
    group = SecureRandom.uuid
    single = original.merge("id" => SecureRandom.uuid, "title" => "No Sunlight", "date" => "2008-04-15",
      "release-group" => { "id" => group, "primary-type" => "Single", "title" => "No Sunlight", "first-release-date" => "2008-04-15" },
      "media" => [ { "position" => 1, "track-count" => 1, "tracks" => [ track ] } ])
    evidence = assessment.evidence.deep_dup
    publication = evidence.dig("recording_publications", NarrowStairsFixture::RECORDING)
    publication["earliest_publication"] = single.slice("id", "title", "date")
    publication["original_groups"] << group
    evidence["construction_editions"] << single
    RecordingResolution::Assessment.create!(group_id: assessment.group_id, version: assessment.version, actor: assessment.actor,
      digest: SecureRandom.hex(32), evidence:)

    get resolution_surface_path(observation)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css(".resolution-context").text).to include("May 13, 2008",
      "April 15, 2008", "Earliest verified recording publication · April 15, 2008")
    expect(doc.css(".resolution-primary").size).to eq(1)
    expect(doc.at_css('input[name="construct_release"]')["value"]).to eq(NarrowStairsFixture::ORIGINAL)
    params = doc.css(".resolution-confirmation input[type=hidden]").to_h { |input| [ input["name"], input["value"] ] }
    params = Rack::Utils.parse_nested_query(Rack::Utils.build_query(params))
    payload = observation.payload
    5.times do |index|
      Scrobble.create!(user:, lastfm_account: observation.lastfm_account, played_at: observation.played_at - (index + 1).hours, payload:)
    end
    expect { post decide_resolution_surface_path(observation), params: }.not_to change(RecordingResolution::Decision, :count)
    expect(flash[:alert]).to include("changed")
    expect(Release.count).to eq(0)

    get resolution_surface_path(observation)
    params = Nokogiri::HTML(response.body).css(".resolution-confirmation input[type=hidden]").to_h { |input| [ input["name"], input["value"] ] }
    params = Rack::Utils.parse_nested_query(Rack::Utils.build_query(params))
    expect(params["construct_release"]).to eq(NarrowStairsFixture::ORIGINAL)
    expect(params["resolution_plan"]).to eq(CanonicalCatalog::ResolutionPlan.new(
      RecordingResolution::Assessment.find(params.fetch("assessment_id")), NarrowStairsFixture::RECORDING, 6).fingerprint)
    post decide_resolution_surface_path(observation), params: params
    expect(flash[:notice]).to(eq("Recording decision saved."), flash[:alert])
    release = Release.sole
    expect(release.ingested_from_release_mbid).to eq(NarrowStairsFixture::ORIGINAL)
    expect(release.catalog_track_slots.base_sequence.count).to eq(11)
    expect(release.catalog_track_slots.additional_appearances).to be_empty
    expect(RecordingResolution::Ledger.for_recordings(user, [ Recording.find_by!(mbid: NarrowStairsFixture::RECORDING).id ]).count(:id)).to eq(6)
    expect(Scrobble.pluck(:payload).uniq).to eq([ payload ])

    request = CatalogImport.where(kind: CatalogImport::RECORDING_METADATA).sole
    selected = original.dig("media", 0, "tracks", 2, "recording")
    data = selected.merge("releases" => [ single, *narrow_stairs_editions ].map { |edition| edition.slice("id", "title") })
    session = double(provenance: [])
    allow(session).to receive(:get).with(:musicbrainz, "/ws/2/recording/#{selected.fetch('id')}", params: anything) do |*_, &projection|
      { "data" => projection.call(data) }
    end
    expect { CanonicalCatalog::Processor.new(request, session_factory: ->(*) { session }).call }.not_to change(Release, :count)
    expect(request.reload.state).to eq("imported")
    get resolution_surface_path(observation)
    expect(Nokogiri::HTML(response.body).at_css('[aria-label="Resolution preview"]').text).to include("0 new releases")
  end

  [ "2008-05-13", "2015-02-24" ].each do |stored_date|
    it "corrects a previously admitted Narrow Stairs source with stored date #{stored_date} only after confirmation" do
      finish_oidc
      user = User.find_by!(oidc_subject: @subject)
      LastfmAccount.associate!(user, "narrow-stairs-correction")
      play, assessment = narrow_stairs_assessment(user)
      editions = narrow_stairs_editions.map { |data| CanonicalCatalog::Edition.new(data, data.fetch("id")) }
      original = CanonicalCatalog::Construction.new(editions)
      later = editions.find { |edition| edition.data["id"] == NarrowStairsFixture::LATER }
      imported = CatalogImport.create!(kind: "release", entity_id: 1, due_at: Time.current, state: "imported")
      source = Struct.new(:provenance).new([])
      release = CanonicalCatalog::Store.new(imported, source).release(later.data.merge("date" => stored_date),
        original.base.slots, checked_editions: original.appearances, additional_slots: original.additional_slots)
      previous = CatalogRevision.find_by!(entity_type: "Release", entity_id: release.id)
      frozen_evidence = previous.evidence

      get resolution_surface_path(play)
      expect(response.body).to include("May 13, 2008", "Reuse existing release", "Resolve this observation")
      expect(release.reload.ingested_from_release_mbid).to eq(NarrowStairsFixture::LATER)
      expect(RecordingResolution::Decision.count).to eq(0)

      post decide_resolution_surface_path(play), params: { scope: "surface", recording_mbid: NarrowStairsFixture::RECORDING,
        assessment_id: assessment.id, construct_release: NarrowStairsFixture::ORIGINAL,
        construction_head: CanonicalCatalog::ReviewedConstruction.head(release) }
      expect(flash[:notice]).to eq("Recording decision saved.")
      expect(Release.sole.id).to eq(release.id)
      expect(release.reload.attributes.values_at("release_year", "release_month", "release_day")).to eq([ 2008, 5, 13 ])
      expect(previous.reload.evidence).to eq(frozen_evidence)
      expect(RecordingResolution::ReleaseTracklist.new(release).evidence).to include("edition_mbid" => NarrowStairsFixture::ORIGINAL)
      decision = RecordingResolution::Decision.sole
      expect(Recording.find(decision.recording_id).mbid).to eq(NarrowStairsFixture::RECORDING)
      background = CatalogImport.create!(kind: "release", entity_id: release.id, due_at: Time.current, state: "imported")
      expect do
        CanonicalCatalog::Store.new(background, source).release(later.data, original.base.slots)
      end.to raise_error(CanonicalCatalog::Store::Unverified, /reviewed original release/)
      expect(RecordingResolution::Decision.sole.id).to eq(decision.id)
      expect(RecordingResolution::ReleaseTracklist.new(release.reload).evidence["edition_mbid"]).to eq(NarrowStairsFixture::ORIGINAL)
    end
  end

  [ "Narrow Stairs", "Time Warner 2", "Incorrect title", nil ].each do |caption|
    it "refreshes original recording evidence independently of album string #{caption.inspect}" do
      finish_oidc
      user = User.find_by!(oidc_subject: @subject)
      LastfmAccount.associate!(user, "original-evidence-refresh")
      play, historical = narrow_stairs_assessment(user, historical: true, album_name: caption)
      saved_payload = play.attributes
      saved_evidence = historical.evidence

      post investigate_resolution_surface_path(play)
      request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
      expect(request.context).to include("refresh" => true, "observation_id" => play.id)
      editions = narrow_stairs_editions.index_by { |edition| edition.fetch("id") }
      recording = saved_evidence["candidates"].first
      browse = narrow_stairs_publications.dig("recording_publications", recording["id"], "appearances")
        .select { |release| release.dig("release-group", "id") == NarrowStairsFixture::GROUP }
      fixture = { "releases" => editions, "searches" => {}, "collections" => { NarrowStairsFixture::GROUP => editions.values },
        "recording_releases" => { recording["id"] => browse } }
      session = DiscoveryReplay::Session.new(fixture,
        { "candidates" => [ recording ], "release_search" => "unused", "verified_recording" => recording })
      CanonicalCatalog::Processor.new(request, session_factory: ->(*) { session }).call
      expect(request.reload.state).to eq("imported")
      get resolution_surface_path(play)
      expect(response.body).to include("May 13, 2008", NarrowStairsFixture::ORIGINAL, "11 tracks")
      expect(RecordingResolution::Assessment.where(group_id: historical.group_id).count).to eq(2)
      expect(historical.reload.evidence).to eq(saved_evidence)
      expect(play.reload.attributes).to eq(saved_payload)
      expect(RecordingResolution::Decision.count).to eq(0)
      expect(Release.count).to eq(0)
    end
  end

  it "constructs and corrects the Guilt Show fixture while assigning the same group" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "guilt-show")
    plays, assessment, recording, original = guilt_show_assessment(user)
    params = { scope: "surface", recording_mbid: recording["id"], assessment_id: assessment.id,
      construct_release: original.dig("release-group", "id") }
    post decide_resolution_surface_path(plays.first), params: params
    expect(flash[:notice]).to eq("Recording decision saved.")
    release = Release.sole
    expect(release.attributes.values_at("release_year", "release_month", "release_day")).to eq([ 2004, 3, 2 ])
    expect(release.catalog_track_slots.base_sequence.count).to eq(13)
    added = release.catalog_track_slots.additional_appearances.sole
    expect(added).to have_attributes(position: 14, appearance_date: "2004-08-21")
    expect(RecordingResolution::Ledger.effective(user).where(id: plays.map(&:id)).map(&:effective_recording_id).uniq).to eq([ added.recording_id ])
    get resolution_surface_path(plays.first)
    expect(response.body).not_to include("Review release correction")

    old_head = CanonicalCatalog::ReviewedConstruction.head(release)
    release.update!(release_day: 3, ingested_from_release_mbid: added.edition_mbid)
    release.catalog_track_slots.base_sequence.first.destroy!
    release.catalog_track_slots.additional_appearances.update_all(appearance_date: "2004-08")
    post decide_resolution_surface_path(plays.first), params: params.merge(
      head: RecordingResolution::Decision.sole.id, construction_head: old_head)
    expect(flash[:alert]).to include("changed")
    expect(release.reload.release_day).to eq(3)
    post decide_resolution_surface_path(plays.first), params: params.merge(
      head: RecordingResolution::Decision.sole.id, construction_head: CanonicalCatalog::ReviewedConstruction.head(release.reload))
    expect(flash[:notice]).to eq("Recording decision saved.")
    expect(Release.sole.id).to eq(release.id)
    expect(release.reload.release_day).to eq(2)
    expect(release.catalog_track_slots.base_sequence.count).to eq(13)
    expect(release.catalog_track_slots.additional_appearances.sole.appearance_date).to eq("2004-08-21")
    expect(RecordingResolution::ReleaseTracklist.new(release).evidence["edition_mbid"]).to eq(original.fetch("id"))
    expect(release.ingested_from_release_mbid).to eq(added.edition_mbid)

    patch chronology_recording_path(added.recording_id),
      params: { chronology: { start_date: "2003", end_date: "2004-01", source: "Session notes" } }
    expect(flash[:notice]).to eq("Recording date saved.")
    get recording_path(added.recording_id)
    expect(response.body).to include("2003 to 2004-01", "First release date reported by MusicBrainz")
  end

  it "appends entity-specific corrections with provenance and rejects unjustified or stale edits" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "colors-owner")
    artist = Artist.create!(name: "Color test", mbid: SecureRandom.uuid)
    endpoint = musical_identity_artist_path(artist)
    patch endpoint, params: { musical_identity: { colors: %w[light-green blue], head: "" } }
    expect(response).to redirect_to(artist_path(artist, anchor: "guide-assignment"))
    first = MusicalIdentityDecision.sole
    expect(first).to have_attributes(entity: artist, user:, colors: %w[light-green blue])

    patch endpoint, params: { musical_identity: { colors: %w[pink], head: "" } }
    patch endpoint, params: { musical_identity: { colors: %w[black blue gray], head: first.id } }
    expect(MusicalIdentityDecision.count).to eq(1)

    patch endpoint, params: { musical_identity: { colors: %w[black blue gray], head: first.id, rationale: "Three distinct musical traits" } }
    latest = MusicalIdentityDecision.latest_for([ artist ]).fetch([ "Artist", artist.id ])
    expect(latest.colors).to eq(%w[black blue gray])
    expect(first.reload.colors).to eq(%w[light-green blue])
  end

  it "counts overlapping listening observations for independently admitted ESTRUS album and single" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "estrus-release-context")
    ids = %w[798b4b4f-07fd-469b-87ad-54f7f9182bca f268e723-fb4d-41bd-9ba8-326b8d9a7fc0 5aef7cd0-1673-473f-bfb2-c2ac4fbe616b]
    editions = ids.to_h { |id| [ id, JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/releases/#{id}.json").read) ] }
    single_data = editions.fetch(ids.first)
    recording_data = single_data.fetch("media").first.fetch("tracks").first.fetch("recording")
      .merge("releases" => editions.values.map { |edition| edition.slice("id", "title") })
    mbid = recording_data.fetch("id")
    payload = { artist_name: "Tove Lo", album_name: "ESTRUS", track_name: "I'm your girl right?", album_mbid: SecureRandom.uuid }
    plays = 8.times.map do |i|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current - i.minutes, payload:)
    end
    original = plays.map(&:payload)
    surface = RecordingResolution::Ledger.attach!(plays.first)
    claims = plays.first.payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims:)
    assessment = RecordingResolution::Assessment.create!(group_id: group.id, version: "release-context", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: { "candidates" => [ recording_data ], "review_tracklists" =>
        editions.transform_values { |edition| RecordingResolution::ReviewRelease.project(edition) } })
    get resolution_surface_path(plays.first, section: "evidence")
    expect(response.body).to include("Resolve 8 observations", "Release tracklist", "candidate recording")
    expect(response.body).not_to include("Verify selected release")

    post decide_resolution_surface_path(plays.first), params: { mode: "resolved", scope: "surface",
      recording_mbid: mbid, assessment_id: assessment.id }
    expect(response).to have_http_status(:see_other)
    request = CatalogImport.where(kind: CatalogImport::RECORDING_METADATA).sole
    session = double(provenance: [])
    allow(session).to receive(:get) do |_provider, path, params:, &projection|
      id = path.split("/").last
      data = id == mbid ? recording_data : editions.fetch(id)
      { "data" => projection.call(data) }
    end
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { session }).call
    expect(request.reload.state).to eq("imported")
    expect(Release.count).to eq(0)
    explicit = CatalogImport.request!("recording", request.entity_id)
    CanonicalCatalog::Processor.new(explicit, session_factory: ->(*) { session }).call
    album = Release.find_by!(title: "ESTRUS")
    single = Release.find_by!(title: "I’m your girl right?")
    recording = Recording.find_by!(mbid:)
    expect(album.catalog_track_slots.base_sequence.count).to eq(13)
    expect(single.catalog_track_slots.count).to eq(1)
    expect(album.release_month).to eq(9)
    expect(single.release_month).to eq(5)
    expect(recording.admitted_releases).to contain_exactly(album, single)
    get resolution_surface_path(plays.first)
    panel = Nokogiri::HTML(response.body).at_css(".review-catalog-context")
    expect(panel.css("dl > div:last-child a").map { |link| link["href"] }).to contain_exactly(release_path(album), release_path(single))
    expect(panel.at_css("dl > div:last-child .review-catalog-mark.present").text).to eq("✓")
    expect(Release.member_recording_ids([ album, single ]).count(recording.id)).to eq(1)
    expect(plays.map { |play| play.reload.payload }).to eq(original)

    [ album, single ].each do |release|
      get release_path(release)
      expect(response.body).to include("8 distinct resolved observations")
      expect(Nokogiri::HTML(response.body).css("#listening-activity > ol > li").size).to eq(8)
    end
    get recording_path(recording)
    expect(response.body).to include("8 resolved listening observations")
    get release_path(album, with_release: [ single.id ])
    expect(response.body).to include("Combined listening history", "8 distinct resolved observations")

    Scrobble.create!(user:, lastfm_account: user.source_account, played_at: 1.day.from_now, payload:)
    get release_path(album, with_release: [ single.id ])
    expect(response.body).to include("9 distinct resolved observations")
    RecordingResolution::Ledger.record!(listener: user, scrobble: plays.last, scope: :scrobble,
      mode: "unresolved", reason: "Individual exception")
    get release_path(album, with_release: [ single.id ])
    expect(response.body).to include("8 distinct resolved observations")

    artist = Artist.find_by!(name: "Tove Lo")
    featured = Artist.create!(name: "Featured artist", mbid: SecureRandom.uuid)
    recording.recording_artists.create!(artist: featured, role: :featured)
    recording.update!(duration_ms: 180_000)
    Scrobble.create!(user:, lastfm_account: user.source_account, played_at: 40.days.ago, payload:)
    missing = Recording.create!(title: "Unknown duration", mbid: SecureRandom.uuid)
    missing.recording_artists.create!(artist: featured, role: :featured)
    extra = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: 2.days.ago,
      payload: { artist_name: "Archive source", track_name: "Unknown duration" })
    RecordingResolution::Ledger.record!(listener: user, scrobble: extra, scope: :scrobble,
      mode: "resolved", recording: missing, reason: "Verified fixture")
    [ artist, featured ].each do |entry|
      get artist_path(entry, range: "30d")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("#artist-recordings tr:first-child td a").text).to include("girl right?")
      expect(document.at_css("#artist-recordings .listening-bar").text).to include("9")
      expect(document.at_css("#listening-history").text).to include("27m estimated listening time")
      expect(document.at_css("#listening-history [aria-current=true]").text).to eq("30d")
      expect(document.css(".artist-timeline-data li").sum { |row| row["data-duration-ms"].to_i }).to eq(1_260_000)
      expect(document.css("#artist-releases .listening-bar").size).to eq(2)
      expect(document.css("#artist-releases .listening-bar").map(&:text)).to all(include("27m"))
    end
    expect(response.body).to include("Duration known for 9 of 10 plays.", "Unknown duration")

    refresh = CatalogImport.request!("recording", recording.id)
    expect do
      CanonicalCatalog::Processor.new(refresh, session_factory: ->(*) { session }).call
    end.not_to change { [ Release.count, Recording.count, Artist.count, CatalogTrackSlot.count ] }
  end

  it "renders the Regent's Court source, three checked tracklists and explicit decision scopes" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "regents-court-review")
    fixture_dir = Rails.root.join("spec/fixtures/recording_resolution/discovery")
    fixture = JSON.parse(fixture_dir.join("corpus.json").read)
    daytrotter = JSON.parse(fixture_dir.join("daytrotter.json").read)
    fixture.fetch("releases")[daytrotter.fetch("id")] = daytrotter
    example = fixture.fetch("cases").find { |row| row["id"] == "regents-court-292999" }
    source = example.fetch("surface")
    claims = example.fetch("claims")
    payload = claims.merge("artist_name" => source.fetch("artist"), "album_name" => source.fetch("album"), "track_name" => source.fetch("track"))
    plays = 5.times.map do |offset|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at: offset.days.ago,
        source_fingerprint: SecureRandom.hex(32), payload:)
    end
    observation = plays.first
    surface = RecordingResolution::Ledger.attach!(observation)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims:)
    session = DiscoveryReplay::Session.new(fixture, example)
    evidence = RecordingResolution::Evaluator.new(session, discogs: nil, workspace: true, review_alternative: true).call(surface, claims)
    # Reproduce the historical scoring that production stored before the caption rule changed.
    evidence["ranking"] = RecordingResolution::Ranking.call(surface, evidence.except("review_tracklists"), caption_bonus: true)
    assessment = RecordingResolution::Assessment.create!(group_id: group.id, version: "fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence:)

    get resolution_surface_path(observation, play: observation.id, assessment: assessment.id, section: "evidence")
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css(".review-heading h1").text).to eq(source.fetch("track"))
    expect(doc.css(".review-source-claims dt").map(&:text)).to eq([ "Artist string", "Album string" ])
    expect(doc.css(".review-source-claims dd").map(&:text)).to eq(source.values_at("artist", "album"))
    expect(doc.css(".review-edition").map(&:text).join(" ")).to include("deluxe edition", "2011", "Daytrotter Session")
    expect(doc.css(".review-candidate").map { |card| card.css(".review-candidate-detail .review-tracks li").size }).to eq([ 18, 14, 4 ])
    expect(doc.css(".review-candidate-detail .review-track-match").size).to eq(3)
    expect(doc.css(".review-score strong").map(&:text)).to eq(%w[9 8 7])
    expect(doc.text).to include("historical scoring", "3 plausible recordings found", "Resolve observation #{observation.id} only", "2:03")

    get resolution_surface_path(observation, assessment: assessment.id)
    expect(response.body).to include("Resolve recording only", "Future exact matches")
    expect(RecordingResolution::Decision.count).to eq(0)
  end

  it "paginates ordered track slots and release appearances without dropping catalog entries" do
    finish_oidc
    recording = Recording.create!(title: "Common recording", mbid: SecureRandom.uuid)
    release = Release.create!(title: "Long release")
    101.times do |i|
      release.catalog_track_slots.create!(recording:, medium: 1, position: i + 1, title: "Slot #{i + 1}", track_mbid: SecureRandom.uuid)
    end
    31.times do |i|
      Release.create!(title: "Appearance %02d" % i).catalog_track_slots.create!(recording:, medium: 1,
        position: 1, title: recording.title, track_mbid: SecureRandom.uuid)
    end

    get release_path(release)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css(".release-tracks tbody tr").size).to eq(100)
    get doc.at_xpath("//a[text()='More tracks']")["href"]
    doc = Nokogiri::HTML(response.body)
    expect(doc.css(".release-tracks tbody tr").map(&:text).join).to include("101", "Slot 101")

    get recording_path(recording)
    doc = Nokogiri::HTML(response.body)
    expect(doc.text).to include("Appearance 29")
    expect(doc.text).not_to include("Appearance 30")
    get doc.at_xpath("//a[text()='More release appearances']")["href"]
    expect(response.body).to include("Appearance 30", "Long release")
  end

  it "protects the library, workspace and import actions" do
    [ artists_path, releases_path, recordings_path, resolution_surfaces_path ].each do |path|
      get path
      expect(response).to redirect_to(root_path)
    end
    get artists_path(profile: "qalephd", action_name: "index")
    expect(response).to redirect_to(root_path)
    post import_artist_path(1)
    expect(response).to redirect_to(root_path)
  end

  it "reviews an exact surface, records explicit choices, rejects stale writes, and respects archive revocation" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-request")
    example = catalog_observation(user)
    second = catalog_observation(user, time: 1.day.ago)
    assessment = catalog_assessment(example)
    mbid = CatalogFixtures::IDS[:studio]
    choice = { mode: "resolved", scope: "surface", recording_mbid: mbid, assessment_id: assessment.id, reason: "Confirmed studio version" }

    get resolution_surfaces_path(filter: "suggested")
    expect(response.body).to include("Signals", "Night Lines", "Night Drive")
    get resolution_surface_path(example)
    expect(response.body).to include("Resolve recording only")
    expect(response.body).not_to include("A checked MusicBrainz edition contains this track slot")
    expect(response.body).not_to include("Release edition to verify")
    get resolution_surface_path(example, before: second.id)
    expect(response.body).to include("2 matching observations")
    expect { post decide_resolution_surface_path(example), params: choice }.to change(RecordingResolution::Decision, :count).by(1)
    expect(response).to redirect_to(resolution_surface_path(example))
    get resolution_surfaces_path(filter: "resolved")
    expect(response.body).to include("Signals")
    get resolution_surfaces_path(filter: "unresolved")
    expect(response.body).not_to include("Signals")
    import = CatalogImport.where(kind: CatalogImport::RECORDING_METADATA).sole
    expect(import.context).not_to have_key("edition_mbid")
    get resolution_surface_path(example)
    expect(response.body).to include("Uncertain release memberships stay pending.")
    expect(response.body).not_to include("Verify selected release", 'name="edition_mbid"')
    expect { post decide_resolution_surface_path(example), params: choice }.not_to change(RecordingResolution::Decision, :count)
    expect(flash[:alert]).to include("changed")

    post decide_resolution_surface_path(example), params: { scope: "scrobble", play_id: second.id, mode: "unresolved" }
    head = RecordingResolution::Decision.last
    expect(head).to have_attributes(scrobble_id: second.id, reason: "Left unresolved",
      evidence: a_hash_including("reason_code" => "left_unresolved"))
    get resolution_surfaces_path(filter: "unresolved")
    row = Nokogiri::HTML(response.body).at_css("tbody tr")
    expect(row.at_css("td.table-number").text).to eq("1")
    expect(row.at_css("th a")["href"]).to eq(resolution_surface_path(second))
    expect(row.text).to include("Candidate found", "Review candidate evidence")
    get resolution_surfaces_path(filter: "exceptions")
    expect(response.body).to include("Signals")
    expect(RecordingResolution::Ledger.effective(user).find(second.id).effective_recording_id).to be_nil
    get resolution_surface_path(example, play: second.id, section: "evidence")
    expect(response.body).to include("Resolve only this observation", "Return this observation to inheritance")
    post decide_resolution_surface_path(example), params: { scope: "scrobble", play_id: second.id, mode: "inherit", head: head.id }
    expect(RecordingResolution::Decision.last.evidence.fetch("reason_code")).to eq("restore_inheritance")
    later = catalog_observation(user, time: 1.day.from_now)
    expect(RecordingResolution::Ledger.effective(user).find(later.id).effective_recording_id).to eq(Recording.find_by!(mbid:).id)
    expect(RecordingResolution::Ledger.effective(user).find(second.id).effective_recording_id).to eq(Recording.find_by!(mbid:).id)

    other = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "other-resolution-listener")
    LastfmAccount.associate!(other, user.source_account.username)
    RecordingResolution::Ledger.record!(listener: other, scrobble: example, scope: :surface, mode: "unresolved", reason: "Other listener private reason")
    get resolution_surface_path(example)
    expect(response.body).not_to include("Other listener private reason")
    get recording_path(Recording.find_by!(mbid:))
    expect(response.body).to include("3 resolved listening observations")
    user.user_lastfm_accounts.active.sole.revoke!
    get resolution_surface_path(example)
    expect(response).to have_http_status(:not_found)
    post decide_resolution_surface_path(example), params: choice
    expect(response).to have_http_status(:not_found)
  end

  it "queues a missing investigation on open, shares the request for exact matches, and shows a worker outcome" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-request")
    observation = catalog_observation(user)
    second = catalog_observation(user, time: 1.day.ago)

    expect { get resolution_surface_path(observation) }.to change(CatalogImport, :count).by(1)
    expect(response.body).to include("Unresolved", "No investigation attempt is scheduled.")
    expect { get resolution_surface_path(second) }.not_to change(CatalogImport, :count)
    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { CatalogFixtures::Session.new }).call
    expect(request.reload.state).to eq("imported")
    get resolution_surface_path(second, section: "evidence")
    expect(response.body).to include("Muzeum’s recommendation", "A checked MusicBrainz edition contains this track slot", "2 matching observations")

    assessment = RecordingResolution::Ledger.assessments(user).sole
    post decide_resolution_surface_path(second), params: { mode: "resolved", scope: "surface",
      recording_mbid: CatalogFixtures::IDS[:studio], assessment_id: assessment.id,
      comment: "Checked the studio version" }
    decision = RecordingResolution::Decision.sole
    expect(decision).to have_attributes(reason: "Confirmed candidate", assessment_id: assessment.id, actor: "listener", user_id: user.id)
    expect(decision.evidence).to include("reason_code" => "confirmed_candidate", "comment" => "Checked the studio version",
      "scoring_version" => RecordingResolution::Ranking::SOURCE_HINTS_VERSION, "affected_scope" => "surface")
    get resolution_surface_path(second, section: "history")
    expect(response.body).to include("Confirmed candidate", "Checked the studio version")
    expect(decision.evidence.fetch("candidate_scores").first.fetch("recording_mbid")).to eq(CatalogFixtures::IDS[:studio])
    snapshot = decision.evidence.fetch("review_snapshot")
    expect(snapshot).to include("feedback" => "selected", "candidate_mbid" => CatalogFixtures::IDS[:studio],
      "affected_observation_count" => 2, "ranking" => assessment.evidence.fetch("ranking"))
    expect(snapshot.fetch("assessment")).to include("id" => assessment.id, "digest" => assessment.digest)
    expect(snapshot.fetch("ranking").first.dig("inputs", "recording_identifier", "weight")).to eq(0)

    post defer_resolution_surface_path(second), params: { feedback: "rejected", assessment_id: assessment.id,
      recording_mbid: CatalogFixtures::IDS[:studio], head: decision.id }
    rejection = RecordingResolution::Decision.last
    expect(rejection).to have_attributes(predecessor_id: decision.id, recording_id: decision.recording_id, mode: "resolved")
    expect(rejection.evidence.fetch("review_snapshot")).to include("feedback" => "rejected",
      "candidate_mbid" => CatalogFixtures::IDS[:studio], "affected_observation_count" => 0)
    expect(RecordingResolution::Ledger.effective(user).find(second.id).effective_recording_id).to eq(decision.recording_id)
    expect(Scrobble.find(observation.id).payload).to eq(observation.payload)
  end

  it "shows an unexpected worker failure as terminal instead of leaving an active lease" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-worker-failure")
    observation = catalog_observation(user)
    get resolution_surface_path(observation)
    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    allow(RecordingResolution::ProviderSession).to receive(:new).and_raise(RuntimeError, "test worker failure")
    expect { CanonicalCatalogJob.perform_now(request.id) }.to raise_error(RuntimeError, "test worker failure")
    expect(request.reload).to have_attributes(state: "failed", lease_until: nil)
    get resolution_surface_path(observation)
    expect(response.body).to include("Failed — Needs Codex")
    expect(response.body).not_to include('class="investigation-progress"')
  end

  it "shows the retained ambiguous Walk ’em With Grace outcome without presenting queued work" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "walk-em-with-grace")
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { artist_name: "The Get Up Kids", album_name: "There Are Rules", track_name: "Walk ’em With Grace" })
    surface = RecordingResolution::Ledger.attach!(observation)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    candidates = %w[0351574e-2b09-4ee0-92ee-4ea9c12f8be6 b05c6f37-1f23-488d-974d-5d062dcf1c9e].map do |mbid|
      { "id" => mbid, "title" => "Walk ’em With Grace", "artist-credit" => [ { "name" => "The Get Up Kids" } ] }
    end
    RecordingResolution::Assessment.create!(group_id: group.id, version: "retained-audit", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: { "candidates" => candidates })
    CatalogImport.create!(kind: RecordingResolution::Investigation::KIND, entity_id: group.id, due_at: Time.current, state: "imported")

    get resolution_surface_path(observation)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".investigation-badge").text).to eq("Needs review")
    expect(page.css(".resolution-choice").size).to eq(2)
    expect(page.at_css(".investigation-progress")).to be_nil
  end

  it "rejects an old identity preview after a source decision changes" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "stale-recording-identity")
    observation, assessment = narrow_stairs_assessment(user)
    mbid = NarrowStairsFixture::RECORDING
    get resolution_surface_path(observation)
    form = Nokogiri::HTML(response.body).at_css(".resolution-confirmation")
    fingerprint = form.at_css('input[name="resolution_plan"]')["value"]
    canonical = Recording.create!(mbid: SecureRandom.uuid, title: "No Sunlight")
    RecordingSourceDecision.revise!(source: assessment.evidence.fetch("candidates").first, recording: canonical,
      expected_head: nil, actor: "operator", reason: "Identity evidence was reviewed")
    post decide_resolution_surface_path(observation), params: { scope: "surface", mode: "resolved",
      recording_mbid: mbid, assessment_id: assessment.id, resolution_plan: fingerprint }
    expect(RecordingResolution::Decision.count).to eq(0)
    expect(Release.count).to eq(0)
    expect(flash[:alert]).to be_present
  end

  it "reports an expired investigation and replaces it only on explicit retry" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-expired-request")
    observation = catalog_observation(user)
    get resolution_surface_path(observation)
    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    request.update!(created_at: 2.days.ago)

    expect { get resolution_surface_path(observation) }.not_to change(CatalogImport, :count)
    expect(response.body).to include("Failed — Retry")
    expect(request.reload.state).to eq("pending")
    expect { post investigate_resolution_surface_path(observation) }.to change(CatalogImport, :count).by(1)
    expect(request.reload.state).to eq("failed")
    expect(CatalogImport.latest(RecordingResolution::Investigation::KIND, request.entity_id).state).to eq("pending")
  end

  it "distinguishes an empty investigation from a provider failure and records a no-change deferral" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-request")
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { "artist_name" => "No Catalog Match", "track_name" => "Unidentified Recording" })
    get resolution_surface_path(observation)
    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { CatalogFixtures::Session.new }).call
    get resolution_surface_path(observation)
    expect(response.body).to include("No recording choices are available")
    expect(response.body).not_to include("Provider evidence unavailable")
    post investigate_resolution_surface_path(observation)
    refreshed = CatalogImport.latest(RecordingResolution::Investigation::KIND, request.entity_id)
    session = instance_double(RecordingResolution::ProviderSession, current_request: { "provider" => "musicbrainz", "endpoint" => "/ws/2/recording" }, provenance: [])
    allow(session).to receive(:get).and_raise(RecordingResolution::ProviderError.new("Fixture outage", terminal: true))
    CanonicalCatalog::Processor.new(refreshed, session_factory: ->(*) { session }).call
    get resolution_surface_path(observation)
    expect(response.body).to include("Provider evidence unavailable")

    post defer_resolution_surface_path(observation), params: { comment: "Investigate later" }
    expect(response).to redirect_to(resolution_surface_path(observation))
    expect(RecordingResolution::Decision.sole).to have_attributes(mode: "inherit",
      evidence: a_hash_including("reason_code" => "deferred_review", "comment" => "Investigate later"))
    expect(RecordingResolution::Ledger.effective(user).find(observation.id).effective_recording_id).to be_nil
  end

  it "distinguishes a legacy partial recording from a canonical provider identity in Resolution and Archive" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-request")
    observation = catalog_observation(user)
    recording = Recording.create!(title: "Legacy recording", mbid: "legacy-reference")
    RecordingResolution::Ledger.record!(listener: user, scrobble: observation, scope: :surface, mode: "resolved",
      reason: "Historical free text", recording:)
    get resolution_surface_path(observation, section: "history")
    expect(response.body).to include("Partially resolved", "Historical free text")
    expect(CatalogImport.count).to eq(0)
    get archive_path
    expect(response.body).to include("Partially resolved", "Reported by Last.fm")
  end
end
