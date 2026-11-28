require "rails_helper"

RSpec.describe MusicalIdentityDecision do
  it "inherits credited artist palettes while preserving direct decisions and abstaining on conflicts" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "identity-cascade")
    artist = Artist.create!(name: "Tove Lo", mbid: SecureRandom.uuid)
    guest = Artist.create!(name: "Guest", mbid: SecureRandom.uuid)
    recording = Recording.create!(title: "Recording", mbid: SecureRandom.uuid)
    recording.recording_artists.create!(artist:, role: :primary)
    recording.recording_artists.create!(artist: guest, role: :featured)
    release = Release.create!(title: "Release")
    release.artists << artist
    decision = described_class.create!(entity: artist, user:, colors: %w[pink gray])
    entries = [ release, recording ]
    release_key = [ "Release", release.id ]
    recording_key = [ "Recording", recording.id ]

    direct, inherited = described_class.presentation_for(entries)
    expect(direct[recording_key]).to be_nil
    expect(inherited[release_key]).to eq(colors: decision.colors, artists: [ artist ])
    expect(inherited[recording_key]).to eq(colors: decision.colors, artists: [ artist ])

    described_class.create!(entity: guest, user:, colors: [ "blue" ])
    expect(described_class.presentation_for(entries).last.keys).to eq([ release_key ])

    override = described_class.create!(entity: recording, user:, colors: [ "yellow" ])
    described_class.create!(entity: artist, user:, colors: [ "blue" ])
    direct, inherited = described_class.presentation_for(entries)
    expect(direct[recording_key]).to eq(override)
    expect(inherited[recording_key]).to be_nil
    expect(inherited[release_key][:colors]).to eq([ "blue" ])

    described_class.create!(entity: recording, user:, colors: [])
    expect(described_class.presentation_for(entries).last[recording_key]).to eq(colors: [ "blue" ], artists: [ guest, artist ])
    expect(described_class.where(entity: recording).count).to eq(2)
  end
end
