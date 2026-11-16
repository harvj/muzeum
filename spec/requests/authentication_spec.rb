require "rails_helper"

RSpec.describe "Authentication", type: :request do
  let!(:user) { User.create!(email_address: "listener@example.com", password: "a long secret password", activated_at: Time.current) }

  def sign_in(password: "a long secret password")
    post session_path, params: { email_address: " LISTENER@example.com ", password: password, user_id: 999 }
  end

  it "protects HTML and Turbo Frame access, leaving liveness public" do
    get root_path, headers: { "Turbo-Frame" => "private" }
    expect(response).to redirect_to(new_session_path)
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  it "authenticates a local identity without a Last.fm account and revokes logout" do
    sign_in
    expect(response).to redirect_to(root_path)
    expect(user.sessions.count).to eq(1)
    get root_path
    expect(response.body).to include("listener@example.com")
    expect(response.headers["Cache-Control"]).to include("no-store")
    delete session_path
    expect(user.sessions.count).to eq(0)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "rejects wrong passwords and inactive legacy source users" do
    sign_in(password: "wrong")
    expect(user.sessions).to be_empty
    legacy = User.create!(lastfm_username: "public_source")
    post session_path, params: { email_address: legacy.lastfm_username, password: "anything" }
    expect(response).to redirect_to(new_session_path)
    expect(Session.count).to eq(0)
  end

  it "rejects expired, disabled and password-reset sessions" do
    sign_in
    user.sessions.update_all(expires_at: 1.minute.ago)
    get root_path
    expect(response).to redirect_to(new_session_path)
    sign_in
    user.update!(disabled_at: Time.current)
    get root_path
    expect(response).to redirect_to(new_session_path)
    user.update!(disabled_at: nil)
    sign_in
    user.update!(password: "a different long password")
    get root_path
    expect(response).to redirect_to(new_session_path)
    expect(user.sessions.count).to eq(0)
  end

  it "rejects forged cookies" do
    cookies[:session_id] = "1"
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "enforces CSRF protection when enabled" do
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    sign_in
    expect(response).to have_http_status(:unprocessable_content)
  ensure
    ActionController::Base.allow_forgery_protection = old
  end
end
