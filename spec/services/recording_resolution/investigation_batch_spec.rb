require "rails_helper"

RSpec.describe "Bounded investigation batch" do
  include ActiveJob::TestHelper

  it "queues the highest-impact groups, resumes, and leaves decisions and observations alone" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "batch-test")
    LastfmAccount.associate!(user, "batch-test")
    account = user.source_account
    %w[Repeated Repeated Single].each_with_index do |title, index|
      Scrobble.create!(user:, lastfm_account: account, played_at: index.hours.ago, source_fingerprint: SecureRandom.hex(32),
        payload: { artist_name: "Artist", album_name: "Album", track_name: title })
    end
    expect { run_batch(user.id, 1) }.not_to change { [ Scrobble.count, RecordingResolution::Decision.count, Recording.count, Release.count ] }
    first = CatalogImport.sole
    expect(Scrobble.find(first.context.fetch("observation_id")).payload["track_name"]).to eq("Repeated")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(CanonicalCatalogJob)

    expect { run_batch(user.id, 1) }.to change(CatalogImport, :count).by(1)
    second = CatalogImport.order(:id).last
    expect(Scrobble.find(second.context.fetch("observation_id")).payload["track_name"]).to eq("Single")
    expect { run_batch(user.id, 1) }.not_to change(CatalogImport, :count)
    expect(RecordingResolution::Decision.count).to eq(0)
    expect(Scrobble.count).to eq(3)
  end

  def run_batch(listener_id, limit)
    previous = ARGV.dup
    ARGV.replace([ listener_id, limit ].map(&:to_s))
    expect { load Rails.root.join("script/resolution_investigation_batch.rb") }.to output(/investigation_ids/).to_stdout
  ensure
    ARGV.replace(previous)
  end
end
