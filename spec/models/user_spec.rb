require "rails_helper"

RSpec.describe User, type: :model do
  it "retains legacy users without activating or inventing credentials" do
    user = User.create!(lastfm_username: "source_only")
    expect(user.login_enabled?).to be(false)
    expect(user.email_address).to be_nil
  end

  it "requires local credentials for activation and rejects short or oversized passwords" do
    user = User.new(activated_at: Time.current)
    expect(user).not_to be_valid
    user.assign_attributes(email_address: "person@example.com", password: "short")
    expect(user).not_to be_valid
    user.password = "é" * 40
    expect(user).not_to be_valid
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
