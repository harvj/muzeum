require "rails_helper"

RSpec.describe ScrobbleResolver do
  describe ".resolve!" do
    let!(:user) { User.create!(lastfm_username: "jimharvey") }

    let(:payload) do
      {
        "artist_name" => "Tristeza",
        "track_name"  => "Golden Hill",
        "album_name"  => "Spine and Sensory",
        "artist_mbid" => "59fc30ef-c110-4d92-9e83-ebb1d7a343fd",
        "track_mbid"  => "3d42c2ec-8554-402f-890d-3d9a77fc1e13",
        "album_mbid"  => "2ab8c444-ec29-4d18-99f2-85331899aa0c"
      }.to_json
    end

    let!(:scrobble) do
      Scrobble.create!(
        user: user,
        played_at: Time.utc(2006, 5, 12, 8, 57, 41),
        payload: payload
      )
    end

    context "when no matching recording surface exists" do
      it "creates a recording surface and links the scrobble" do
        expect {
          described_class.resolve!(scrobble)
        }.to change(RecordingSurface, :count).by(1)

        scrobble.reload
        surface = scrobble.recording_surface

        expect(surface.artist_name).to eq("Tristeza")
        expect(surface.track_name).to eq("Golden Hill")
        expect(surface.album_name).to eq("Spine and Sensory")

        expect(surface.artist_mbid).to eq("59fc30ef-c110-4d92-9e83-ebb1d7a343fd")
        expect(surface.track_mbid).to eq("3d42c2ec-8554-402f-890d-3d9a77fc1e13")
        expect(surface.album_mbid).to eq("2ab8c444-ec29-4d18-99f2-85331899aa0c")

        expect(surface.normalized_key).to eq("tristeza||spine and sensory||golden hill")
        expect(surface.observed_count).to eq(1)
      end
    end

    context "when a matching recording surface already exists" do
      before do
        described_class.resolve!(scrobble)
      end

      it "reuses the existing recording and reinforces the surface" do
        new_scrobble = Scrobble.create!(
          user: user,
          played_at: Time.utc(2006, 5, 13, 9, 0, 0),
          payload: payload
        )

        expect {
          described_class.resolve!(new_scrobble)
        }.not_to change(Recording, :count)

        surface = RecordingSurface.first

        expect(surface.observed_count).to eq(2)

        new_scrobble.reload
        expect(new_scrobble.recording).to eq(scrobble.recording)
      end
    end

    context "when the scrobble is already resolved" do
      it "does nothing" do
        described_class.resolve!(scrobble)

        expect {
          described_class.resolve!(scrobble)
        }.to change(Recording, :count).by(0)
          .and change(RecordingSurface, :count).by(0)

        expect(scrobble.reload.recording_id).to eq(scrobble.recording_id)
      end
    end
  end
end
