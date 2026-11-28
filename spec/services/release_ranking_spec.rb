require "rails_helper"

RSpec.describe ReleaseRanking do
  it "ranks supported original contexts and first-publication compilations while preserving listener overrides" do
    listener = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "release-ranking-listener")
    other = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "release-ranking-other")
    album, single, compilation, reissue, first_compilation = %w[album single compilation reissue first-compilation].map do |title|
      Release.create!(title:, catalog_verified_at: Time.current, ingested_from_release_mbid: SecureRandom.uuid)
    end
    recording = Recording.create!(title: "No Sunlight", mbid: SecureRandom.uuid)
    [ album, single, compilation, reissue, first_compilation ].each do |release|
      release.catalog_track_slots.create!(recording:, title: recording.title, track_mbid: SecureRandom.uuid, medium: 1, position: 1)
    end
    album.catalog_track_slots.create!(recording:, title: recording.title, track_mbid: SecureRandom.uuid, medium: 1, position: 2)
    releases = [ album, single, compilation, reissue, first_compilation ]
    request = CatalogImport.create!(kind: "release", entity_id: album.id, state: "imported", due_at: Time.current)
    [ album, single ].each do |release|
      CatalogRevision.create!(catalog_import: request, entity_type: "Release", entity_id: release.id,
        evidence: { "edition_mbid" => release.ingested_from_release_mbid, "original_context" => true })
    end
    CatalogRevision.create!(catalog_import: request, entity_type: "Recording", entity_id: recording.id,
      evidence: { "verified_publication" => { "id" => first_compilation.ingested_from_release_mbid, "date" => "2008-04-01" } })

    ranked = lambda do |user|
      ranking = described_class.new(user, releases)
      releases.select { |release| ranking.include?(release) }
    end
    expect(ranked.call(listener)).to contain_exactly(album, single, first_compilation)
    ranking = described_class.new(listener, releases)
    expect(ranking.include?(reissue, has_plays: true)).to be true
    expect(ranking.include?(Release.new(title: "Unverified"), has_plays: true)).to be false
    expect(Release.member_recording_ids(releases)).to eq([ recording.id ])

    ReleaseRankingDecision.create!(user: listener, release: album, included: false)
    ReleaseRankingDecision.create!(user: listener, release: compilation, included: true)
    expect(ranked.call(listener)).to contain_exactly(single, compilation, first_compilation)
    expect(described_class.new(listener, releases).include?(album, has_plays: true)).to be false
    expect(ranked.call(other)).to contain_exactly(album, single, first_compilation)

    ReleaseRankingDecision.create!(user: listener, release: album, included: true)
    expect(ranked.call(listener)).to contain_exactly(album, single, compilation, first_compilation)
    expect(ReleaseRankingDecision.where(user: listener, release: album).order(:id).pluck(:included)).to eq([ false, true ])
  end
end
