require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  it "accepts a recent authenticated Muzeum session" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "catalog-connection")
    session = user.sessions.create!(expires_at: 1.day.from_now, last_seen_at: Time.current,
      verified_at: Time.current, grant_token: "fixture")
    cookies.signed[:session_id] = session.id

    connect

    expect(connection.session_id).to eq(session.id)
  end

  it "rejects anonymous, expired and stale verification" do
    expect { connect }.to have_rejected_connection

    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "catalog-stale-connection")
    session = user.sessions.create!(expires_at: 1.day.from_now, last_seen_at: Time.current,
      verified_at: 61.seconds.ago, grant_token: "fixture")
    cookies.signed[:session_id] = session.id
    expect { connect }.to have_rejected_connection

    session.update!(expires_at: 1.second.ago, verified_at: Time.current)
    expect { connect }.to have_rejected_connection
  end
end
