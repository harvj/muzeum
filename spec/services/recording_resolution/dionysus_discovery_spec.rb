require "rails_helper"

RSpec.describe RecordingResolution::EditionDiscovery do
  let(:digital) { JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/releases/dionysus_digital.json").read) }
  let(:group) { digital.fetch("release-group") }
  let(:credits) { digital.fetch("artist-credit") }
  let(:combined) do
    { "id" => "b6936149-67dd-42eb-ae78-05dac370a3da",
      "title" => "Act I: Sea Borne / Liberator of Minds / Dance of the Bacchantes",
      "length" => 1_002_226, "artist-credit" => credits }
  end
  let(:physical) { JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/releases/dionysus_cd.json").read) }
  let(:client) { instance_double(Clients::Musicbrainz) }
  let(:session) { instance_double(RecordingResolution::ProviderSession, provenance: []) }

  it "recovers distinct split movements from a complete same-day edition after the indexed result contains only the combined act" do
    expect(client).to receive(:collection_editions).with(session, group.fetch("id"), limit: 25)
      .twice.and_return([ physical, digital ])
    expect(client).to receive(:edition).with(session, digital.fetch("id"), catalog: true).twice.and_return(digital)

    digital.fetch("media").first.fetch("tracks").first(2).each do |slot|
      surface = RecordingResolution::RealCorpusEvaluation::Observation.new(
        artist: "Dead Can Dance", album: "Dionysus", track: slot.fetch("title"))
      discovery = described_class.new(client, session)
      found = discovery.call(surface, [ combined ], checked: physical, attempted: physical.fetch("id"), search: false, origins: false)
      expect(found.pluck("id")).to eq([ slot.dig("recording", "id") ])
      expect(found.first.fetch("release_discovery")).to include(
        "id" => digital.fetch("id"), "position" => slot.fetch("position"), "track_length" => slot.fetch("length"))
      tracklist = discovery.tracklists.fetch(digital.fetch("id"))
      expect(tracklist.fetch("state")).to eq("complete")
      expect(discovery.construction_editions.fetch(digital.fetch("id")).fetch("media").first.fetch("tracks").pluck("id"))
        .to eq(digital.fetch("media").first.fetch("tracks").pluck("id"))

      ranks = RecordingResolution::Ranking.call(surface,
        { "candidates" => [ combined.merge("releases" => [ physical ]), *found ], "review_tracklists" => discovery.tracklists },
        source_hints: true)
      expect(ranks.pluck("recording_mbid")).to eq([ slot.dig("recording", "id"), combined.fetch("id") ])
      expect(ranks.first.dig("inputs", "title", "state")).to eq("positive")
      expect(ranks.last.dig("inputs", "title", "state")).to eq("contradictory")
      expect(RecordingResolution::Ranking.recommended?(ranks)).to be_falsey
    end
  end
end
