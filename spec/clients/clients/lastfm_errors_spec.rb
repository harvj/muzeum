require "rails_helper"

RSpec.describe "Last.fm failure evidence" do
  before { stub_const("ENV", ENV.to_h.merge("LASTFM_API_KEY" => "synthetic-only-key")) }
  let(:client) { Clients::Lastfm.new(username: "synthetic") }

  { 11 => Clients::NetworkError, 16 => Clients::NetworkError, 29 => Clients::RateLimited, 10 => Clients::Unauthorized }.each do |code, type|
    it "classifies envelope #{code} without losing the raw error evidence" do
      raw = "<lfm status='failed'><error code='#{code}'>provider error</error></lfm>"
      stub_request(:get, /ws.audioscrobbler.com/).to_return(body: raw)
      expect { client.recent_tracks }.to raise_error(type) { |error| expect(error.raw_body).to eq(raw) }
    end
  end

  it "honors Retry-After and retains HTTP error bodies" do
    stub_request(:get, /ws.audioscrobbler.com/).to_return(status: 429, headers: { "Retry-After" => "180" }, body: "throttled")
    expect { client.recent_tracks }.to raise_error(Clients::RateLimited) do |error|
      expect(error.retry_after).to eq(180)
      expect(error.raw_body).to eq("throttled")
    end
    expect(IngestionBudget.find_by!(name: "lastfm").next_request_at).to be >= 179.seconds.from_now
  end

  it "normalizes transport failures without leaking query credentials" do
    stub_request(:get, /ws.audioscrobbler.com/).to_timeout
    expect { client.recent_tracks }.to raise_error(Clients::NetworkError) { |error| expect(error.message).not_to include("synthetic-only-key") }
  end
end
