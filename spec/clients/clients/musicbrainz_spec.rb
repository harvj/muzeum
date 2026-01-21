require "rails_helper"

RSpec.describe Clients::Musicbrainz do
  let(:client) { described_class.new }

  let(:base_url) { "https://musicbrainz.org/ws/2" }

  let(:recording_response) do
    {
      "recordings" => [
        {
          "id" => "mbid-123",
          "title" => "Test Recording",
          "length" => 217000,
          "artist-credit" => [
            { "name" => "Test Artist", "artist" => { "id" => "artist-mbid" } }
          ]
        }
      ]
    }
  end

  describe "#search_recordings" do
    before do
      stub_request(:get, "#{base_url}/recording")
        .with(
          query: hash_including(
            "query" => /artist:"Test Artist"/,
            "fmt"   => "json"
          )
        )
        .to_return(
          status: 200,
          body: recording_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns recordings from MusicBrainz" do
      results = client.search_recordings(
        artist: "Test Artist",
        recording:  "Test Recording"
      )

      expect(results).to be_an(Array)
      expect(results.length).to eq(1)
      expect(results.first["id"]).to eq("mbid-123")
    end

    it "raises ArgumentError when artist is missing" do
      expect {
        client.search_recordings(recording: "Test Recording")
      }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when recording is missing" do
      expect {
        client.search_recordings(artist: "Test Artist")
      }.to raise_error(ArgumentError)
    end
  end

  describe "#fetch_recording" do
    before do
      stub_request(:get, "#{base_url}/recording/mbid-123")
        .with(query: { "fmt" => "json" })
        .to_return(
          status: 200,
          body: { "id" => "mbid-123", "title" => "Test Recording" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "fetches a recording by mbid" do
      result = client.fetch_recording("mbid-123")

      expect(result["id"]).to eq("mbid-123")
      expect(result["title"]).to eq("Test Recording")
    end
  end

  describe "error handling" do
    it "raises RateLimited on 429" do
      stub_request(:get, "#{base_url}/recording")
        .with(query: hash_including("fmt" => "json"))
        .to_return(status: 429)

      expect {
        client.search_recordings(
          artist: "Test Artist",
          recording:  "Test Recording"
        )
      }.to raise_error(Clients::RateLimited)
    end

    it "raises Unauthorized on 401" do
      stub_request(:get, "#{base_url}/recording")
        .with(query: hash_including("fmt" => "json"))
        .to_return(status: 401)

      expect {
        client.search_recordings(
          artist: "Test Artist",
          recording:  "Test Recording"
        )
      }.to raise_error(Clients::Unauthorized)
    end

    it "raises InvalidResponse on non-200 responses" do
      stub_request(:get, "#{base_url}/recording")
        .with(query: hash_including("fmt" => "json"))
        .to_return(status: 500)

      expect {
        client.search_recordings(
          artist: "Test Artist",
          recording:  "Test Recording"
        )
      }.to raise_error(Clients::InvalidResponse)
    end
  end
end
