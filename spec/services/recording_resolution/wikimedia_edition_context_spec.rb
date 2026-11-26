require "rails_helper"

RSpec.describe Clients::Wikimedia do
  it "retains the Wikipedia section, revision and citation without making a recording identity claim" do
    session = instance_double(RecordingResolution::ProviderSession)
    html = <<~HTML
      <table class="tracklist">
        <caption>Japanese edition bonus tracks</caption>
        <tr><td>12.</td><td>"Mind Over Time"<sup class="reference"><a href="#cite_note-1">[1]</a></sup></td><td>4:49</td></tr>
      </table>
    HTML
    allow(session).to receive(:get).with(:wikipedia, "/w/api.php", params: hash_including(page: "Our Love to Admire"), projection: anything) do |*_, &projection|
      { "data" => projection.call("parse" => { "revid" => 123, "text" => html }) }
    end

    note = described_class.new(session).edition_notes("Our Love to Admire", "Mind Over Time").sole
    expect(note).to eq("heading" => "Japanese edition bonus tracks",
      "url" => "https://en.wikipedia.org/w/index.php?oldid=123",
      "citations" => [ "https://en.wikipedia.org/w/index.php?oldid=123#cite_note-1" ])
  end
end
