require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/leisure_configurations_fixture"

RSpec.describe "Release configurations", type: :request do
  include OidcFlow
  include LeisureConfigurationsFixture
  before { prepare_oidc }
  after { restore_oidc }

  it "projects verified Leisure sequences, release dates and distinct listening per listener" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "leisure-configurations")
    source = JSON.parse(Rails.root.join("docs/design/release-configurations/tracklists.json").read)
    editions = source.fetch("leisure_editions").index_by { |edition| edition.fetch("date") }
    uk, us, japan, anniversary = editions.values_at("1991-08-27", "1991-09-24", "1991-09-20", "2012-08-01")
    release = Release.create!(title: "Leisure", release_group_mbid: uk.fetch("release_group"),
      release_year: 1991, release_month: 8, release_day: 27, catalog_verified_at: Time.current)

    snapshots = [ uk, us, japan, anniversary ].map do |edition|
      snapshot = ReleaseConfiguration.retain!(release, source_edition(edition), provenance: { "fixture" => "Leisure evidence" })
      expect(snapshot.tracks.pluck("track_mbid")).to eq(edition.fetch("media").flat_map { |medium| medium.fetch("tracks").pluck("track_mbid") })
      snapshot
    end
    uk_config, us_config, japan_config, anniversary_config = snapshots
    extra = (us_config.tracks.pluck("source_recording_mbid") - uk_config.tracks.pluck("source_recording_mbid")).first
    source_track = us_config.tracks.find { |track| track["source_recording_mbid"] == extra }
    recording = Recording.create!(title: source_track.fetch("title"), mbid: extra, duration_ms: 180_000)
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: 2.days.ago,
      payload: { artist_name: "Blur", track_name: recording.title, album_name: "Leisure" })
    RecordingResolution::Ledger.record!(listener: user, scrobble: observation, scope: :surface, mode: "resolved",
      reason: "Fixture", recording:)
    other = User.create!(oidc_subject: "other-leisure")
    ReleaseConfigurationDecision.select!(other, release, japan_config)

    expect do
      patch configuration_release_path(release), params: { configuration_id: us_config.id }
      expect(response).to have_http_status(:see_other)
      get release_path(release)
      expect(response.body).to include("September 24, 1991", "1 distinct resolved observation", "3 min")
      get releases_path(release_month: "1991-09", sort: "release_date")
      expect(response.body).to include("Leisure", "September 24, 1991")
      patch configuration_release_path(release), params: { configuration_id: uk_config.id }
      get release_path(release)
      expect(response.body).to include("August 27, 1991", "0 distinct resolved observations")
      get releases_path(release_month: "1991-09")
      expect(response.body).not_to include("Leisure")
      patch configuration_release_path(release), params: { configuration_id: us_config.id }
      get release_path(release)
      expect(response.body).to include("1 distinct resolved observation")
      patch configuration_release_path(release), params: { configuration_id: anniversary_config.id }
    end.not_to change { [ Scrobble.count, RecordingResolution::Decision.count, CatalogTrackSlot.count, Recording.count ] }

    expect(ReleaseConfigurationSelection.new(other, [release.id]).date(release).iso).to eq("1991-09-20")
    expect(EffectiveReleaseDate.for(release.reload).iso).to eq("1991-08-27")
    repeated = source_edition(us)
    medium = repeated.fetch("media").first
    track = medium.fetch("tracks").find { |row| row.dig("recording", "id") == extra }
    medium.fetch("tracks") << track.merge("id" => SecureRandom.uuid, "position" => medium.fetch("tracks").size + 1)
    medium["track-count"] = medium.fetch("tracks").size
    repeated_config = ReleaseConfiguration.retain!(release, repeated, provenance: { "fixture" => "Repeated slot" })
    ReleaseConfigurationDecision.select!(user, release, repeated_config)
    expect(ReleaseConfigurationSelection.new(user, [release.id]).memberships).to eq([[release.id, recording.id]])
    expect(ReleaseConfigurationDecision.where(user:, release:).count).to eq(5)
    get recording_path(recording)
    expect(response.body).to include("1 resolved listening observation")
  end

  it "retains checked configurations as evidence and admits only an explicitly selected adjacent single" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "adjacent-leisure")
    evidence = JSON.parse(Rails.root.join("docs/design/release-configurations/tracklists.json").read)
    uk = source_edition(evidence.fetch("leisure_editions").find { |edition| edition["country"] == "GB" })
    anniversary = source_edition(evidence.fetch("leisure_editions").find { |edition| edition["id"].start_with?("5834") })
    single = source_edition(evidence.fetch("adjacent_program_editions").find { |edition| edition["id"].start_with?("b11e") })
    single["release-group"].merge!("title" => single.fetch("title"), "primary-type" => "Single", "first-release-date" => single.fetch("date"))
    credits = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/discovery/blur-checked-editions.json").read).first.fetch("artist-credit")
    single["artist-credit"] = credits
    single.fetch("media").each do |medium|
      medium.fetch("tracks").each { |track| track["artist-credit"] = credits }
    end
    source_mbid = "87dfe8ce-4861-4327-b16c-60423529e352"
    album = Release.create!(title: "Leisure", catalog_verified_at: Time.current, release_group_mbid: uk.dig("release-group", "id"))
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { artist_name: "Blur", track_name: "She’s So High", album_name: "Leisure" })
    surface = RecordingResolution::Ledger.attach!(observation)
    claims = observation.payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
    group = RecordingResolution::Group.create!(surface_id: surface.id, claims:, version: RecordingResolution::Ledger::VERSION)
    assessment = RecordingResolution::Assessment.create!(group_id: group.id, version: "fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: {
        construction_editions: [ uk, anniversary ],
        additional_recording_publications: {
          source_mbid => { exact_recording: { id: source_mbid }, adjacent_programs: [ single ],
            releases: [ { id: single.fetch("id"), slots: [ { position: 2 } ] } ] }
        }
      })

    expect do
      post retain_configuration_resolution_surface_path(observation),
        params: { assessment_id: assessment.id, edition_mbid: anniversary.fetch("id") }
    end.to change { album.release_configurations.count }.by(1)
    expect(CatalogTrackSlot.count).to eq(0)
    expect(Recording.count).to eq(0)
    expect do
      post admit_adjacent_release_resolution_surface_path(observation),
        params: { assessment_id: assessment.id, edition_mbid: single.fetch("id"), recording_mbid: source_mbid }
    end.to change(Release, :count).by(1)
    expect(response).to have_http_status(:see_other)
    admitted = Release.find_by!(ingested_from_release_mbid: single.fetch("id"))
    expect(admitted.catalog_track_slots.base_sequence.order(:medium, :position).pluck(:source_recording_mbid))
      .to eq(single.fetch("media").flat_map { |medium| medium.fetch("tracks").map { |track| track.dig("recording", "id") } })
    expect(RecordingResolution::Decision.count).to eq(0)
    expect(Scrobble.count).to eq(1)
  end

  it "preserves partial and unknown date precision in catalog queries" do
    year = EffectiveReleaseDate.new("1991")
    expect(year.iso).to eq("1991")
    expect(year.within?(from: Date.new(1991, 9, 1), through: Date.new(1991, 9, 30))).to be(false)
    expect(EffectiveReleaseDate.new("1991-09-31").iso).to be_nil
    expect(EffectiveReleaseDate.new(nil).within?(from: Date.new(1991, 9, 1))).to be_falsey
  end
end
