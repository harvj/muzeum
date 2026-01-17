require "rails_helper"

RSpec.describe Lastfm::RecentTracksParser do
  let(:xml) do
    <<~XML
      <recenttracks user="qalep">
        <track>
          <artist mbid="2f9ecbed-27be-40e6-abca-6de49d50299e">
            Aretha Franklin
          </artist>
          <name>Sisters Are Doing It For Themselves</name>
          <mbid></mbid>
          <album mbid=""></album>
          <date uts="1213031819">9 Jun 2008, 17:16</date>
        </track>
      </recenttracks>
    XML
  end

  it "parses metadata without tracks" do
    meta = described_class.parse(xml, no_tracks: true)
    expect(meta[:user]).to eq "qalep"
  end

  it "parses tracks into normalized hashes" do
    tracks = described_class.parse(xml)[:tracks]

    expect(tracks.length).to eq(1)

    track = tracks.first

    expect(track[:artist_name]).to eq("Aretha Franklin")
    expect(track[:artist_mbid]).to eq("2f9ecbed-27be-40e6-abca-6de49d50299e")
    expect(track[:track_name]).to eq("Sisters Are Doing It For Themselves")
    expect(track[:track_mbid]).to be_nil
    expect(track[:album_mbid]).to be_nil
    expect(track[:played_at]).to eq(Time.at(1213031819).utc)
  end
end
