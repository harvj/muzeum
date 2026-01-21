require "rails_helper"

RSpec.describe RecordingResolver do
  describe ".resolve!" do
    let!(:provisional) do
      Recording.create!(
        title: "The Hop",
        mbid: nil,
        status: :provisional,
        confidence: 0.6,
        source: "lastfm"
      )
    end

    let!(:scrobble) do
      Scrobble.create!(
        recording: provisional,
        played_at: Time.current,
        user: User.create!(lastfm_username: "foo"),
        payload: { track_name: "The Hop" }
      )
    end

    let(:mbid)  { "2e83c377-32fb-4b6b-941f-3ca7e84130fd" }
    let(:title) { "The Hop" }

    context "when no canonical recording exists for the MBID" do
      it "promotes the provisional recording to canonical" do
        canonical = described_class.resolve!(
          provisional_recording: provisional,
          mbid: mbid,
          title: title
        )

        expect(canonical).to eq(provisional)
        expect(canonical.mbid).to eq(mbid)
        expect(canonical.status).to eq("canonical")
        expect(canonical.confidence).to eq(1.0)
        expect(canonical.source).to eq("musicbrainz")
      end

      it "keeps existing scrobbles attached" do
        canonical = described_class.resolve!(
          provisional_recording: provisional,
          mbid: mbid,
          title: title
        )

        expect(scrobble.reload.recording_id).to eq(canonical.id)
      end
    end

    context "when a canonical recording already exists for the MBID" do
      let!(:canonical) do
        Recording.create!(
          title: "The Hop",
          mbid: mbid,
          status: :canonical,
          confidence: 1.0,
          source: "musicbrainz"
        )
      end

      it "merges the provisional recording into the canonical one" do
        resolved = described_class.resolve!(
          provisional_recording: provisional,
          mbid: mbid,
          title: title
        )

        expect(resolved).to eq(canonical)

        expect(provisional.reload.merged_into_id).to eq(canonical.id)
        expect(provisional.status).to eq("merged")
      end

      it "reassigns scrobbles to the canonical recording" do
        described_class.resolve!(
          provisional_recording: provisional,
          mbid: mbid,
          title: title
        )

        expect(scrobble.reload.recording_id).to eq(canonical.id)
      end
    end

    context "when resolving the same recording twice" do
      it "is idempotent" do
        first = described_class.resolve!(
          provisional_recording: provisional,
          mbid: mbid,
          title: title
        )

        second = described_class.resolve!(
          provisional_recording: provisional,
          mbid: mbid,
          title: title
        )

        expect(second.id).to eq(first.id)
        expect(Recording.where(mbid: mbid).count).to eq(1)
      end
    end

    context "when MBID is missing" do
      it "raises a ResolutionError" do
        expect {
          described_class.resolve!(
            provisional_recording: provisional,
            mbid: nil,
            title: title
          )
        }.to raise_error(RecordingResolver::ResolutionError)
      end
    end
  end
end
