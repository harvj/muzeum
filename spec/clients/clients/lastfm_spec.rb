require "rails_helper"

RSpec.describe Clients::Lastfm do
  let(:client) { described_class.new(username: "foo") }

  let(:xml_response) do
    <<~XML
      <lfm status="ok">
        <recenttracks user="foo">
          <track>
            <name>Test Track</name>
          </track>
        </recenttracks>
      </lfm>
    XML
  end

  before do
    allow(ENV).to receive(:fetch)
      .with("LASTFM_API_KEY")
      .and_return("test_api_key")
  end

  before do
    stub_request(:get, "https://ws.audioscrobbler.com/2.0/")
      .with(
        query: hash_including(
          method: "user.getrecenttracks",
          user: "foo",
          format: "xml",
          limit: "200" # NOTE: query params are strings
        )
      )
      .to_return(
        status: 200,
        body: xml_response,
        headers: { "Content-Type" => "application/xml" }
      )
  end

  it "returns raw XML" do
    result = client.recent_tracks(from: nil)

    expect(result).to be_a(String)
    expect(result).to include("<recenttracks")
  end
end
