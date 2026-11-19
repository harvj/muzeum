require "rails_helper"
require "tmpdir"
require_relative "../support/oidc_flow"

RSpec.describe "Listening archive", type: :request do
  include OidcFlow
  before { prepare_oidc; finish_oidc }
  after { restore_oidc }

  it "associates only the authenticated user after public username validation" do
    stub_request(:get, /ws.audioscrobbler.com/).to_return(body: '<lfm status="ok"><user><name>Listener</name></user></lfm>')
    stub_const("ENV", ENV.to_h.merge("LASTFM_API_KEY" => "test-key"))
    patch lastfm_account_path, params: { lastfm_username: "Listener", user_id: 999 }
    expect(User.find_by!(oidc_subject: @subject).lastfm_username).to eq("Listener")
    post imports_path
    run = ImportRun.last
    expect(run.source_username).to eq("Listener")
    expect(run.upper_bound).to be_present
    expect { post imports_path }.not_to change(ImportRun, :count)
  end

  it "handles invalid names and upstream outages without changing the association" do
    patch lastfm_account_path, params: { lastfm_username: "../bad" }
    expect(User.last.lastfm_username).to be_nil
    stub_const("ENV", ENV.to_h.merge("LASTFM_API_KEY" => "test-key"))
    stub_request(:get, /ws.audioscrobbler.com/).to_return(status: 503)
    patch lastfm_account_path, params: { lastfm_username: "someone" }
    expect(User.last.lastfm_username).to be_nil
  end

  it "recognizes delayed publication on the next request and hides a mismatched tag" do
    Dir.mktmpdir do |directory|
      path = Pathname(directory).join("PUBLISHED_RELEASE")
      sha = "a" * 40
      allow(Rails.configuration.x).to receive(:published_release_path).and_return(path)
      allow(Rails.configuration.x).to receive(:running_revision).and_return(sha)

      get archive_path
      expect(Nokogiri::HTML(response.body).at_css(".site-footer").text).not_to include("Muzeum v")

      path.write("#{sha} v0.2.1\n")
      get archive_path
      expect(Nokogiri::HTML(response.body).at_css(".site-footer").text).to include("Muzeum v0.2.1")

      path.write("#{'b' * 40} v0.2.2\n")
      get archive_path
      expect(Nokogiri::HTML(response.body).at_css(".site-footer").text).not_to include("Muzeum v")
    end
  end

  it "computes statistics from only the user's persisted observations" do
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "stats-fixture")
    user.scrobbles.create!(played_at: Time.utc(2020), payload: { artist_name: "Artist", album_name: "Album", track_name: "Track" })
    user.scrobbles.create!(played_at: Time.utc(2021), payload: { artist_name: "Artist", album_name: "", track_name: "Other" })
    other = User.create!(lastfm_username: "other")
    other.scrobbles.create!(played_at: Time.utc(1999), payload: { artist_name: "Private Artist" })
    get archive_path
    expect(response.body).to include("01 Jan 2020", "01 Jan 2021", "Observed artists", "Observed albums", "Observed tracks")
    expect(response.body).not_to include("1999", "Private Artist", "User management")
    expect(response.body).to include("https://funding.harvj.com/", "harvj-session")
    expect(controller.instance_variable_get(:@artists)).to eq(1)
    expect(controller.instance_variable_get(:@albums)).to eq(1)
    expect(controller.instance_variable_get(:@tracks)).to eq(2)
  end
end
