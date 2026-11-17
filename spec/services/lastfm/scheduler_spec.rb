require "rails_helper"

RSpec.describe Lastfm::Scheduler do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { User.create!(lastfm_username: "scheduled", oidc_issuer: OidcClient::ISSUER, oidc_subject: "scheduled") }
  let(:account) { user.source_account }
  before { stub_const("ENV", ENV.to_h.merge("LASTFM_SYNC_ENABLED" => "1")) }

  it "is centrally gated and recovers lost queue delivery from a durable lease" do
    account.update!(sync_enabled: true)
    expect { described_class.dispatch! }.to have_enqueued_job(SyncAccountJob).with(account.id)
    expect(described_class.dispatch!).to eq(0)
    travel 31.seconds
    expect { described_class.dispatch! }.to have_enqueued_job(SyncAccountJob).with(account.id)
    stub_const("ENV", ENV.to_h.merge("LASTFM_SYNC_ENABLED" => "0"))
    expect(described_class.dispatch!).to eq(0)
  end

  it "selects the longest overdue source first and reserves one schedule for shared users" do
    account.update!(sync_enabled: true, next_poll_at: 2.hours.ago)
    second_user = User.create!(lastfm_username: "other", oidc_issuer: OidcClient::ISSUER, oidc_subject: "other")
    second = second_user.source_account
    second.update!(sync_enabled: true, next_poll_at: 1.hour.ago)
    LastfmAccount.associate!(second_user, account.username)
    expect { described_class.dispatch!(limit: 1) }.to have_enqueued_job(SyncAccountJob).with(account.id)
    expect { described_class.dispatch!(limit: 1) }.to have_enqueued_job(SyncAccountJob).with(second.id)
  end

  it "resumes the same durable run after a service restart instead of creating another writer" do
    first = described_class.run_for!(account)
    expect(described_class.run_for!(account).id).to eq(first.id)
    expect(first.actor_kind).to eq("scheduler")
    account.update!(sync_enabled: true)
    allow(Lastfm::HistoricalImporter).to receive(:new).and_raise(Lastfm::Deferred.new(3))
    SyncAccountJob.perform_now(account.id)
    expect(account.reload.dispatch_until).to be > Time.current
    expect(account.import_runs.count).to eq(1)
  end

  it "persists bounded retries and circuit-breaker pauses, and stops on source drift" do
    run = described_class.run_for!(account)
    5.times { described_class.failure!(run, Clients::NetworkError.new) }
    expect(run.reload).to be_paused
    expect(run.retry_count).to eq(5)
    expect(run.retry_at).to be >= 899.seconds.from_now
    expect(IngestionIssue.where(kind: "retry").count).to eq(5)
    described_class.failure!(run, Lastfm::SourceDrift.new)
    expect(account.reload.state).to eq("paused")
  end

  it "permits separate accounts associated with one principal to progress independently" do
    second = LastfmAccount.associate!(user, "second-source")
    first_run = described_class.run_for!(account)
    second_run = described_class.run_for!(second)
    expect(first_run.lastfm_account_id).not_to eq(second_run.lastfm_account_id)
    expect(first_run.user_id).to eq(second_run.user_id)
  end

  it "uses bounded windows to drain a long outage without skipping the backlog" do
    account.update!(synced_through: 30.days.ago.to_i)
    run = described_class.run_for!(account)
    expect(run.kind).to eq("incremental")
    expect(run.upper_bound - run.lower_bound).to eq(7.days.to_i)
    expect(run.lower_bound).to eq(account.synced_through - 48.hours.to_i)
  end

  it "replays incremental drift within the original fixed interval with a bounded generation budget" do
    account.update!(synced_through: 2000)
    run = described_class.run_for!(account)
    original_bounds = [ run.lower_bound, run.upper_bound ]
    3.times do |index|
      described_class.failure!(run, Lastfm::SourceDrift.new)
      expect(account.reload.state).to eq("active")
      travel_to(run.retry_at + 1.second)
      run = described_class.run_for!(account)
      expect([ run.lower_bound, run.upper_bound ]).to eq(original_bounds)
      expect(run.authorization_context["drift_generation"]).to eq(index + 1)
    end
    described_class.failure!(run, Lastfm::SourceDrift.new)
    expect(account.reload.state).to eq("paused")
  end

  it "continues under a new service authorization when one requester leaves a shared archive" do
    membership = user.user_lastfm_accounts.sole
    other = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "remaining-source-viewer")
    LastfmAccount.associate!(other, account.username)
    run = account.import_runs.create!(user: user, source_username: account.username, upper_bound: 2000, next_page: 3, actor_kind: "user")
    membership.revoke!
    described_class.failure!(run, Lastfm::PermissionDenied.new)
    expect(account.reload.state).to eq("active")
    continuation = described_class.run_for!(account)
    expect(continuation.id).not_to eq(run.id)
    expect(continuation.next_page).to eq(3)
    expect(continuation.authorization_context["continued_from_run_id"]).to eq(run.id)
    expect(continuation.actor_kind).to eq("scheduler")
  end

  it "does not run for revoked or disabled memberships even if the job was already queued" do
    account.update!(sync_enabled: true)
    user.user_lastfm_accounts.sole.revoke!
    expect(Lastfm::HistoricalImporter).not_to receive(:new)
    SyncAccountJob.perform_now(account.id)
    expect(account.reload.state).to eq("paused")
  end
end

RSpec.describe Lastfm::RequestBudget do
  it "serializes all source requests through one durable database budget" do
    described_class.acquire!
    expect { described_class.acquire! }.to raise_error(Lastfm::Deferred)
    expect(IngestionBudget.where(name: "lastfm").count).to eq(1)
  end

  it "honors a provider-wide cooldown" do
    described_class.acquire!
    described_class.cooldown!(120)
    expect(IngestionBudget.find_by!(name: "lastfm").next_request_at).to be >= 119.seconds.from_now
  end
end
