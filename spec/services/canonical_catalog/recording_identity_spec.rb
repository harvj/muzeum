require "rails_helper"

RSpec.describe CanonicalCatalog::RecordingIdentity do
  let(:user) { User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "identity-review", lastfm_username: "identity-review") }
  let(:credit) { [ { "name" => "Artist", "artist" => { "id" => SecureRandom.uuid, "name" => "Artist" } } ] }
  let(:explicit) { { "id" => SecureRandom.uuid, "title" => "Signal", "length" => 187_400, "disambiguation" => "explicit", "artist-credit" => credit } }
  let(:clean) { explicit.merge("id" => SecureRandom.uuid, "disambiguation" => "clean", "length" => 187_000, "edit_recording_mbids" => [ explicit.fetch("id") ]) }
  let(:assessment) { double(id: 42, evidence: { "candidates" => [ clean, explicit ] }) }

  it "links corroborated source IDs under one recording and revises without changing its source slot" do
    identity = described_class.new(assessment, clean.fetch("id"))
    recording = identity.apply!(assessment, user)
    expect(recording.mbid).to eq(explicit.fetch("id"))
    expect(CanonicalCatalog::Store.recording!(clean)).to eq(recording)
    expect(Recording.count).to eq(1)
    first = RecordingSourceDecision.sole
    expect(first.evidence.fetch("source")).to eq(clean)

    release = Release.create!(title: "Album", ingested_from_release_mbid: SecureRandom.uuid, catalog_verified_at: Time.current)
    slot = release.catalog_track_slots.create!(recording:, source_recording_mbid: clean.fetch("id"), title: "Signal",
      track_mbid: SecureRandom.uuid, medium: 1, position: 1)
    digest = Digest::SHA256.hexdigest([ [ 1, 1, clean.fetch("id") ] ].to_json)
    request = CatalogImport.create!(kind: "release", entity_id: release.id, state: "imported", due_at: Time.current)
    CatalogRevision.create!(catalog_import: request, entity_type: "Release", entity_id: release.id,
      evidence: { "track_count" => 1, "tracklist_digest" => digest, "edition_mbid" => release.ingested_from_release_mbid })
    fingerprint = RecordingResolution::ReleaseTracklist.new(release).evidence.fetch("tracklist_digest")
    other = Recording.create!(mbid: SecureRandom.uuid, title: "Reviewed alternative")
    before = described_class.new(assessment, clean.fetch("id")).signature
    RecordingSourceDecision.revise!(source: clean, recording: other, expected_head: first.id, actor: "operator", reason: "Reviewed evidence")
    expect(described_class.new(assessment, clean.fetch("id")).signature).not_to eq(before)
    expect(slot.reload).to have_attributes(recording: other, source_recording_mbid: clean.fetch("id"))
    expect(RecordingResolution::ReleaseTracklist.new(release).evidence.fetch("tracklist_digest")).to eq(fingerprint)
    expect(RecordingSourceDecision.order(:id).pluck(:recording_id)).to eq([ recording.id, other.id ])
    expect do
      RecordingSourceDecision.revise!(source: clean, recording:, expected_head: first.id, actor: "operator", reason: "Stale review")
    end.to raise_error(ActiveRecord::StaleObjectError)
  end

  it "leaves separately cataloged sources distinct even with corroborating evidence" do
    canonical = [ clean, explicit ].map { |source| CanonicalCatalog::Store.recording!(source) }
    expect(described_class.new(assessment, clean.fetch("id")).apply!(assessment, user)).to eq(canonical.first)
    expect(RecordingSourceDecision.count).to eq(0)
    expect do
      RecordingSourceDecision.revise!(source: clean, recording: canonical.last, expected_head: nil, actor: "operator", reason: "Review")
    end.to raise_error(CanonicalCatalog::Store::Unverified)
  end

  it "keeps title and duration matches and alternate mixes separate without identity corroboration" do
    clean_without_evidence = clean.except("edit_recording_mbids")
    remix = clean.merge("id" => SecureRandom.uuid, "disambiguation" => "remix")
    evidence = double(evidence: { "candidates" => [ clean_without_evidence, explicit, remix ] })
    identity = described_class.new(evidence, explicit.fetch("id"))
    expect(identity.source_ids).to eq([ explicit.fetch("id") ])
    expect(identity.aliases).to be_empty
  end
end
