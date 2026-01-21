require "rails_helper"

RSpec.describe Musicbrainz::ReleaseCandidateExtractor do
  let(:recordings) do
    [
      {
        "id" => "rec-1",
        "title" => "The Hop",
        "disambiguation" => "",
        "artist-credit" => [
          { "artist" => { "name" => "A Tribe Called Quest" } }
        ],
        "releases" => [
          {
            "id" => "rel-1",
            "title" => "Beats, Rhymes and Life",
            "date" => "1996-07-30",
            "country" => "US",
            "release-group" => {
              "id" => "rg-1",
              "primary-type" => "Album",
              "secondary-types" => []
            },
            "media" => [
              { "format" => "CD" }
            ]
          }
        ]
      }
    ]
  end

  subject(:candidates) { described_class.call(recordings) }

  it "returns one candidate per recording per release" do
    expect(candidates.length).to eq(1)
  end

  it "extracts release identity and grouping metadata" do
    candidate = candidates.first

    expect(candidate.release_mbid).to eq("rel-1")
    expect(candidate.release_title).to eq("Beats, Rhymes and Life")
    expect(candidate.release_date).to eq("1996-07-30")

    expect(candidate.release_group_mbid).to eq("rg-1")
    expect(candidate.release_group_primary_type).to eq("Album")
    expect(candidate.release_group_secondary_types).to eq([])
  end

  it "extracts country and formats" do
    candidate = candidates.first

    expect(candidate.country).to eq("US")
    expect(candidate.formats).to contain_exactly("CD")
  end

  it "extracts recording and artist metadata" do
    candidate = candidates.first

    expect(candidate.recording_mbid).to eq("rec-1")
    expect(candidate.recording_title).to eq("The Hop")
    expect(candidate.artist_credit).to eq([ "A Tribe Called Quest" ])
  end
end
