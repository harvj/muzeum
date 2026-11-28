require "rails_helper"
require_relative "../support/oidc_flow"

RSpec.describe "Application Shell evidence", type: :request do
  include OidcFlow
  before { prepare_oidc }
  after { restore_oidc }

  it "requires a local session and never issues evidence to signed-out requests" do
    get application_shell_path
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "validates Auth's acceptance cases using confidential form introspection" do
    finish_oidc
    local_session = Session.last
    binding = ApplicationShellEvidence.session_binding(local_session)
    payload = {
      version: "1", iss: OidcClient::ISSUER, aud: "muzeum-test", sub: @subject,
      grant_binding: Digest::SHA256.hexdigest(local_session.grant_token), preferred_username: "alex",
      eligible_destination_ids: %w[continuum-engine missing remote-gaming muzeum],
      iat: 20.seconds.ago.to_i, exp: 40.seconds.from_now.to_i
    }
    stub_request(:get, "#{OidcClient::ISSUER}/.well-known/oauth-authorization-server")
      .to_return(body: { issuer: OidcClient::ISSUER, introspection_endpoint_auth_methods_supported: [ "client_secret_basic" ], introspection_endpoint: "#{OidcClient::ISSUER}/introspect" }.to_json)
    fixtures = JSON.parse(file_fixture("application_shell/auth-v1.json").read).fetch("cases")
    fixtures.each do |fixture|
      scenario = fixture.fetch("case")
      evidence = payload.dup
      active = scenario != "revoked-or-missing-grant"
      evidence[:eligible_destination_ids] = [] if scenario == "no-eligible-destinations"
      evidence[:aud] = "other-client" if scenario == "cross-client-or-subject"
      evidence[:exp] = Time.current.to_i if scenario == "expired-evidence"
      stub_request(:post, "#{OidcClient::ISSUER}/introspect")
        .with(basic_auth: %w[muzeum-test test-only-secret], body: {
          token: local_session.grant_token, token_type_hint: "refresh_token", application_shell_version: "1"
        }).to_return(status: scenario.start_with?("auth-outage") ? 503 : 200, headers: { "Cache-Control" => "no-store" },
        body: { active: active, application_shell: evidence }.to_json)
      supplied_binding = scenario == "replaced-local-session" ? "0" * 64 : binding
      get application_shell_path, headers: { "X-Muzeum-Shell-Session" => supplied_binding }
      if %w[verified no-eligible-destinations].include?(scenario)
        expect(response).to have_http_status(:ok), scenario
        result = response.parsed_body
        expect(result.fetch("username")).to eq("alex")
        expected = scenario == "verified" ? %w[remote-gaming continuum-engine] : []
        expect(result.fetch("applications").pluck("id")).to eq(expected)
      else
        expect(response).to have_http_status(scenario == "replaced-local-session" ? :unauthorized : :service_unavailable), scenario
        expect(response.body).to be_empty
      end
    end
    expect(WebMock).to have_requested(:post, "#{OidcClient::ISSUER}/introspect").times(7)
  end

  it "renders the verified login name independently of unavailable grant evidence" do
    finish_oidc(claims: { preferred_username: "jim" })
    local_session = Session.last
    get archive_path
    expect(Nokogiri::HTML(response.body).at_css('[data-application-shell-target="username"]').text).to eq("jim")

    binding = ApplicationShellEvidence.session_binding(local_session)
    local_session.update!(verified_at: 61.seconds.ago)
    stub_request(:post, "#{OidcClient::ISSUER}/introspect").to_return(status: 503)
    get application_shell_path, headers: { "X-Muzeum-Shell-Session" => binding }
    expect(response).to have_http_status(:service_unavailable)
    expect(Session.exists?(local_session.id)).to be(true)

    stub_request(:post, "#{OidcClient::ISSUER}/introspect").to_return(body: { active: false }.to_json)
    get application_shell_path, headers: { "X-Muzeum-Shell-Session" => binding }
    expect(response).to have_http_status(:unauthorized)
    expect(Session.exists?(local_session.id)).to be(false)
    get root_path
    expect(response.body).to include("Log In")
    expect(response.body).not_to include('data-application-shell-target="username"')
  end

  it "updates identity only from newer evidence and retains it when grants cannot be verified" do
    finish_oidc(claims: { preferred_username: "original" })
    local_session = Session.last
    headers = { "X-Muzeum-Shell-Session" => ApplicationShellEvidence.session_binding(local_session) }
    initial = local_session.shell_username_issued_at
    provider = instance_double(OidcClient)
    allow(OidcClient).to receive(:new).and_return(provider)

    allow(provider).to receive(:shell_evidence).and_return(
      { username: "renamed", ids: [], issued_at: initial + 1, expires_at: 30.seconds.from_now.to_i },
      { username: "original", ids: [], issued_at: initial, expires_at: 30.seconds.from_now.to_i }
    )
    2.times do
      get application_shell_path, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("username" => "renamed", "applications" => [])
    end
    allow(provider).to receive(:shell_evidence).and_raise(OidcClient::Failure)
    get application_shell_path, headers: headers
    expect(response).to have_http_status(:service_unavailable)
    get archive_path
    expect(Nokogiri::HTML(response.body).at_css('[data-application-shell-target="username"]').text).to eq("renamed")
  end

  it "does not authorize a page bound to the session replaced by a new login" do
    finish_oidc
    original = ApplicationShellEvidence.session_binding(Session.last)
    delete session_path
    finish_oidc
    expect(ApplicationShellEvidence.session_binding(Session.last)).not_to eq(original)
    get application_shell_path, headers: { "X-Muzeum-Shell-Session" => original }
    expect(response).to have_http_status(:unauthorized)
  end
end
