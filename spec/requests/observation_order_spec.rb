require "rails_helper"
require_relative "../support/oidc_flow"

RSpec.describe "Listening observation order", type: :request do
  include OidcFlow
  before { prepare_oidc }
  after { restore_oidc }

  it "paginates Resolution and recording observations by played_at and breaks ties by ID" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "observation-order")
    stamp = 4.days.ago.change(usec: 0)
    timestamps = [ stamp + 3.hours, stamp, stamp + 3.hours, *(1..29).map { |offset| stamp + offset.minutes } ]
    plays = timestamps.map do |played_at|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at:,
        payload: { artist_name: "Blur", album_name: "Leisure", track_name: "Birthday - 2012 Remaster" })
    end
    recording = Recording.create!(title: "Birthday", mbid: SecureRandom.uuid)
    RecordingResolution::Ledger.record!(listener: user, scrobble: plays.first, scope: :surface, mode: "resolved",
      recording:, reason: "Chronological fixture")
    expected = plays.sort_by { |play| [ play.played_at, play.id ] }.reverse

    [ resolution_surface_path(plays.first, section: "observations"), recording_path(recording, details: "1") ].each do |url|
      get url
      first = Nokogiri::HTML(response.body)
      expect(first.css("time[datetime]").map { |node| node["datetime"] } & expected.map { |play| play.played_at.iso8601 })
        .to eq(expected.first(30).map { |play| play.played_at.iso8601 }.uniq)
      pagination = first.css("a").find { |node| node.text == "Older observations" }
      expect(Rack::Utils.parse_query(URI.parse(pagination["href"]).query)["before"]).to eq(expected[29].id.to_s)
      get pagination["href"].split("#").first
      second = Nokogiri::HTML(response.body)
      expect(second.css("time[datetime]").map { |node| node["datetime"] } & expected.map { |play| play.played_at.iso8601 })
        .to eq(expected.drop(30).map { |play| play.played_at.iso8601 })
    end
    expect(RecordingResolution::Workspace.new(user).matching_page(plays.first, before_id: nil).first.take(2))
      .to eq([ plays[2].id, plays[0].id ])
  end
end
