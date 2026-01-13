require "rails_helper"

RSpec.describe Lastfm::Importer do
  let(:user) { User.create!(lastfm_username: "foo") }

  let(:client) do
    double("Lastfm::Client", recent_scrobbles: scrobbles)
  end

  let(:scrobbles) do
    [
      {
        artist: "Aretha Franklin",
        artist_mbid: "2f9ecbed-27be-40e6-abca-6de49d50299e",
        name: "Sisters Are Doing It For Themselves",
        mbid: nil,
        played_at: Time.utc(2008, 6, 9, 17, 16)
      },
      {
        artist: "Aretha Franklin",
        artist_mbid: "2f9ecbed-27be-40e6-abca-6de49d50299e",
        name: "Sisters Are Doing It For Themselves",
        mbid: nil,
        played_at: Time.utc(2008, 6, 9, 19, 42)
      }
    ]
  end

  it "aggregates listens by day and recording" do
    importer = described_class.new(user, client: client)

    expect {
      importer.run
    }.to change { DailyListen.count }.by(1)

    daily = DailyListen.first
    expect(daily.listen_count).to eq(2)
    expect(daily.date).to eq(Date.new(2008, 6, 9))
  end
end
