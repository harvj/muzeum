require "rails_helper"

RSpec.describe "Source preservation", type: :model do
  it "rejects bulk mutation and deletion of source fields while allowing downstream links" do
    user = User.create!(lastfm_username: "immutable")
    event = user.scrobbles.create!(played_at: Time.utc(2020), payload: { artist_name: "Reported" })
    expect { Scrobble.transaction(requires_new: true) { Scrobble.where(id: event.id).update_all(payload: {}) } }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect { Scrobble.transaction(requires_new: true) { Scrobble.where(id: event.id).delete_all } }.to raise_error(ActiveRecord::StatementInvalid, /retained/)
    expect { event.update!(recording_surface_id: nil) }.not_to raise_error
    expect(event.reload.payload).to eq("artist_name" => "Reported")
  end

  it "retains raw page bytes independently of interpretations" do
    run = User.create!(lastfm_username: "raw").import_runs.create!
    raw = ImportPage.create!(import_run: run, number: 1, raw_body: "<raw/>", checksum: Digest::SHA256.hexdigest("<raw/>"))
    expect { ImportPage.transaction(requires_new: true) { raw.update!(raw_body: "changed") } }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect(raw.reload.raw_body).to eq("<raw/>")
  end
end
