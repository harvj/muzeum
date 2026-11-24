require "rails_helper"

RSpec.describe ReleaseTrackListeningDecision do
  it "applies the latest preference per listener, release and recording and deduplicates edition appearances" do
    listener = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "track-preference-listener")
    other_listener = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "track-preference-other")
    album = Release.create!(title: "Album")
    single = Release.create!(title: "Single")
    base = Recording.create!(title: "Base", mbid: SecureRandom.uuid)
    bonus = Recording.create!(title: "Bonus", mbid: SecureRandom.uuid)
    [ [ album, base, nil ], [ album, base, SecureRandom.uuid ], [ album, bonus, SecureRandom.uuid ], [ single, bonus, nil ] ].each do |release, recording, edition_mbid|
      release.catalog_track_slots.create!(recording:, medium: 1, position: 1, track_mbid: SecureRandom.uuid,
        title: recording.title, edition_mbid:)
    end

    projection = ->(user) { described_class.included_memberships(user, [ album.id, single.id ]).pluck(:release_id, :recording_id) }
    expect(projection.call(listener)).to contain_exactly([ album.id, base.id ], [ single.id, bonus.id ])
    described_class.create!(user: listener, release: album, recording: bonus, included: true)
    described_class.create!(user: listener, release: album, recording: base, included: false)
    expect(projection.call(listener)).to contain_exactly([ album.id, base.id ], [ album.id, bonus.id ], [ single.id, bonus.id ])
    expect(projection.call(other_listener)).to contain_exactly([ album.id, base.id ], [ single.id, bonus.id ])
    album.catalog_track_slots.base_sequence.where(recording: base).delete_all
    album.catalog_track_slots.where(recording: bonus).update_all(edition_mbid: nil)
    expect(projection.call(listener)).to contain_exactly([ album.id, bonus.id ], [ single.id, bonus.id ])
    expect(projection.call(other_listener)).to contain_exactly([ album.id, bonus.id ], [ single.id, bonus.id ])
  end
end
