require "rails_helper"

RSpec.describe Lastfm::Importer do
  let(:user)   { User.create!(lastfm_username: "foo") }
  let(:client) { double("Clients::Lastfm") }

  let(:xml_page_1) do
    <<~XML
      <lfm status="ok">
        <recenttracks user="foo" page="1" perPage="200" totalPages="1" total="2">
          <track>
            <artist mbid="a1">Artist</artist>
            <name>Track One</name>
            <date uts="1000">date</date>
          </track>
          <track>
            <artist mbid="a1">Artist</artist>
            <name>Track Two</name>
            <date uts="2000">date</date>
          </track>
        </recenttracks>
      </lfm>
    XML
  end

  let(:xml_page_2) do
    <<~XML
      <lfm status="ok">
        <recenttracks user="foo" page="1" perPage="200" totalPages="0" total="0">>
        </recenttracks>
      </lfm>
    XML
  end

  it "imports scrobbles and creates an import run" do
    allow(client).to receive(:recent_tracks)
      .with(from: nil, limit: 200)
      .and_return(xml_page_1)

    allow(client).to receive(:recent_tracks)
      .with(page: 1, from: nil, limit: 200)
      .and_return(xml_page_1)

    allow(client).to receive(:recent_tracks)
      .with(from: 2001, limit: 200)
      .and_return(xml_page_2)

    importer = described_class.new(user, client: client)

    expect {
      importer.run
    }.to change { Scrobble.count }.by(2)
     .and change { ImportRun.count }.by(1)

    run = user.import_runs.last

    expect(run.status).to eq("completed")
    expect(run.scrobbles_processed).to eq(2)
    expect(run.range_start_at).to eq(Time.at(1000).utc)
    expect(run.range_end_at).to eq(Time.at(2000).utc)
  end

  it "does not duplicate scrobbles on re-run" do
    allow(client).to receive(:recent_tracks)
      .and_return(xml_page_1, xml_page_1, xml_page_2)

    importer = described_class.new(user, client: client)

    importer.run
    expect(Scrobble.count).to eq 2
    expect { importer.run }.not_to change { Scrobble.count }
  end
end
