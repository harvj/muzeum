require "rails_helper"
require_relative "../support/oidc_flow"

RSpec.describe "Authenticated dashboard synchronization", type: :request do
  include OidcFlow
  before { prepare_oidc; finish_oidc }
  after { restore_oidc }

  it "returns committed page rows as Turbo Streams and skips an unchanged version" do
    user = User.find_by!(oidc_subject: @subject)
    account = LastfmAccount.associate!(user, "shared-dashboard")
    get dashboard_updates_path, params: { version: account.updated_at.iso8601(6) }
    expect(response).to have_http_status(:no_content)
    user.scrobbles.create!(played_at: Time.utc(2025), payload: { artist_name: "New source artist", track_name: "Completion" })
    account.touch
    get dashboard_updates_path, params: { version: "old" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('target="archive_dashboard"', "shared-dashboard", "Completion", "2025-01-01T00:00:00Z")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "rechecks associations and never accepts a request-selected source or actor" do
    user = User.find_by!(oidc_subject: @subject)
    account = LastfmAccount.associate!(user, "authorized")
    other = User.create!(lastfm_username: "private-source")
    get dashboard_updates_path, params: { lastfm_account_id: other.source_account.id }
    expect(response.body).to include("authorized")
    expect(response.body).not_to include("private-source")
    user.user_lastfm_accounts.sole.revoke!
    get dashboard_updates_path, params: { version: account.updated_at.iso8601(6) }
    expect(response.body).not_to include('source-name">authorized')
    delete session_path
    get dashboard_updates_path
    expect(response).to redirect_to(new_session_path)
  end
end
