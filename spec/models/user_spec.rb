require "rails_helper"

RSpec.describe User, type: :model do
  it "retains legacy users without activating or inventing credentials" do
    user = User.create!(lastfm_username: "source_only")
    expect(user.login_enabled?).to be(false)
    expect(user.email_address).to be_nil
  end

  it "requires an Auth subject for login, never local credentials" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "stable-uuid")
    expect(user.login_enabled?).to be(true)
    expect(user.password_digest).to be_nil
    expect(user).not_to respond_to(:authenticate)
    user.update!(disabled_at: Time.current)
    expect(user.login_enabled?).to be(false)
  end

  it "normalizes and uniquely constrains email addresses in the database" do
    user = User.create!(email_address: " Person@example.com ")
    expect(user.email_address).to eq("person@example.com")
    expect { User.transaction(requires_new: true) { User.insert_all!([ { email_address: "PERSON@example.com" } ]) } }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "does not delete listening history when a user is deleted" do
    user = User.create!(lastfm_username: "retained")
    user.scrobbles.create!(played_at: Time.current, payload: { track: "unchanged" })
    expect { user.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect(user.scrobbles.count).to eq(1)
  end
end
