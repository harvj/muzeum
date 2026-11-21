require "rails_helper"
require_relative "../support/oidc_flow"

RSpec.describe "Application Shell evidence", type: :request do
  include OidcFlow
  include ActiveSupport::Testing::TimeHelpers

  before { prepare_oidc }
  after { restore_oidc }

  it "renders the current year across rollover and uses the canonical credit destination" do
    [ Time.utc(2026, 12, 31, 23, 59), Time.utc(2027, 1, 1) ].each do |time|
      travel_to(time) do
        get root_path
        footer = Nokogiri::HTML(response.body).at_css(".site-footer")
        expect(footer.text).to include("© #{time.year}")
        expect(footer.at_css("a")["href"]).to eq("https://harvj.com")
      end
    end
  end

  it "asks Auth for the current session's grant evidence only, then fails closed on revocation" do
    get application_shell_path
    expect(response).to have_http_status(:unauthorized)
    finish_oidc
    now = Time.current.to_i
    grant = "revocable-grant"
    body = { active: true, application_shell: {
      version: "1", iss: OidcClient::ISSUER, aud: "muzeum-test", sub: @subject,
      grant_binding: Digest::SHA256.hexdigest(grant), preferred_username: "alex",
      eligible_destination_ids: [ "continuum" ], iat: now, exp: now + 60
    } }
    request = stub_request(:post, "#{OidcClient::ISSUER}/introspect")
      .with(basic_auth: [ "muzeum-test", "test-only-secret" ], body: {
        token: grant, token_type_hint: "refresh_token", application_shell_version: "1"
      }).to_return(body: body.to_json).then.to_return(body: { active: false }.to_json)
    allow(ApplicationShellRegistry).to receive(:destinations).with([ "continuum" ])
      .and_return([ { name: "Library", url: "https://library.harvj.com/" } ])
    get archive_path
    account = Nokogiri::HTML(response.body).at_css('a[href="https://auth.harvj.com/account?client_id=muzeum-test"]')
    expect(account&.text).to eq("Account Settings")
    expect(request).not_to have_been_requested
    get application_shell_path
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.parsed_body).to eq("username" => "alex", "expires_at" => now + 60,
      "destinations" => [ { "name" => "Library", "url" => "https://library.harvj.com/" } ])
    get application_shell_path
    expect(response).to have_http_status(:no_content)
    expect(request).to have_been_requested.twice
  end
end
