require "rails_helper"
require_relative "../support/oidc_flow"

RSpec.describe "OIDC authentication", type: :request do
  include OidcFlow
  before { prepare_oidc }
  after { restore_oidc }

  it "protects routes and Turbo frames while leaving liveness public" do
    get root_path, headers: { "Turbo-Frame" => "private" }
    expect(response).to redirect_to(new_session_path)
    patch lastfm_account_path, params: { lastfm_username: "someone" }
    expect(response).to redirect_to(new_session_path)
    post imports_path
    expect(response).to redirect_to(new_session_path)
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  it "validates an issued token, persists subject identity, continues sessions and logs out" do
    state = finish_oidc
    expect(response).to redirect_to(root_path)
    user = User.find_by!(oidc_subject: @subject)
    expect(user.oidc_issuer).to eq(OidcClient::ISSUER)
    expect(user.password_digest).to be_nil
    expect(user.sessions.count).to eq(1)
    expect(Session.connection.select_value("SELECT grant_token FROM sessions LIMIT 1")).not_to include("revocable-grant")
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    get "/oidc/callback", params: { state: state, code: "one-use-code" }
    expect(response).to redirect_to(new_session_path)
    delete session_path
    expect(user.sessions.count).to eq(0)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  [ { iss: "https://evil.test" }, { aud: "other-client" }, { nonce: "wrong" }, { exp: 1 }, { iat: 1.day.from_now.to_i }, { azp: "other" } ].each do |claims|
    it "rejects invalid token claims #{claims.keys.join(',')}" do
      finish_oidc(claims: claims)
      expect(response).to redirect_to(new_session_path)
      expect(Session.count).to eq(0)
    end
  end

  it "consumes expired and browser-mismatched attempts without creating a session" do
    post session_path
    attempt = OidcAttempt.last
    attempt.update!(expires_at: 1.second.ago)
    get "/oidc/callback", params: { state: attempt.state, code: "x" }
    expect(OidcAttempt.exists?(attempt.id)).to be(false)
    expect(Session.count).to eq(0)
    post session_path
    attempt = OidcAttempt.last
    attempt.update!(browser_digest: Digest::SHA256.hexdigest("another browser"))
    get "/oidc/callback", params: { state: attempt.state, code: "x" }
    expect(Session.count).to eq(0)
    expect(OidcAttempt.exists?(attempt.id)).to be(false)
  end

  it "rejects token signature manipulation" do
    finish_oidc(key: OpenSSL::PKey::RSA.generate(2048))
    expect(response).to redirect_to(new_session_path)
    expect(Session.count).to eq(0)
  end

  it "rejects missing or expired state and never links by email" do
    User.create!(lastfm_username: "legacy", email_address: "listener@example.com")
    get "/oidc/callback", params: { state: "forged", code: "x" }
    expect(Session.count).to eq(0)
    expect { finish_oidc }.to change(User, :count).by(1)
    expect(User.find_by!(lastfm_username: "legacy").oidc_subject).to be_nil
  end

  it "bounds inactivity, absolute lifetime and disabled identities" do
    finish_oidc
    Session.update_all(last_seen_at: 13.hours.ago)
    get root_path
    expect(response).to redirect_to(new_session_path)
    finish_oidc
    User.find_by!(oidc_subject: @subject).update!(disabled_at: Time.current)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "checks native grant revocation after 60 seconds and fails closed on outages" do
    finish_oidc
    Session.update_all(verified_at: 61.seconds.ago)
    stub_request(:post, "https://auth.harvj.com/introspect").to_return(status: 503)
    get root_path
    expect(response).to redirect_to(new_session_path)
    expect(Session.count).to eq(1)
    stub_request(:post, "https://auth.harvj.com/introspect").to_return(body: { active: false }.to_json)
    get root_path
    expect(Session.count).to eq(0)
  end

  it "supports continuity beyond access-token expiry with matching active grant" do
    finish_oidc
    Session.update_all(verified_at: 6.minutes.ago, created_at: 6.minutes.ago)
    stub_request(:post, "https://auth.harvj.com/introspect").to_return(body: { active: true, client_id: "muzeum-test" }.to_json)
    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "rejects introspection for another client or a conflicting returned subject" do
    finish_oidc
    Session.update_all(verified_at: 61.seconds.ago)
    stub_request(:post, "https://auth.harvj.com/introspect").to_return(body: { active: true, client_id: "wrong" }.to_json)
    get root_path
    expect(Session.count).to eq(0)
    finish_oidc
    Session.update_all(verified_at: 61.seconds.ago)
    stub_request(:post, "https://auth.harvj.com/introspect").to_return(body: { active: true, client_id: "muzeum-test", sub: "wrong" }.to_json)
    get root_path
    expect(Session.count).to eq(0)
  end

  it "rejects forged cookies and enforces CSRF" do
    cookies[:session_id] = "1"
    get root_path
    expect(response).to redirect_to(new_session_path)
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post session_path
    expect(response).to have_http_status(:unprocessable_content)
  ensure
    ActionController::Base.allow_forgery_protection = old
  end
end
