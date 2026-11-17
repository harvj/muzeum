namespace :lastfm do
  desc "Add provenance locators to retained P1.1 pages, without rewriting observations"
  task backfill_provenance: :environment do
    total = 0
    loop do
      count = Lastfm::LegacyProvenance.backfill!
      total += count
      puts "Committed provenance pages: #{total}"
      break if count.zero?
    end
  end
end

namespace :lastfm do
  desc "Inspect persisted account coverage/provenance without provider calls"
  task :status, [ :username ] => :environment do |_task, args|
    account = LastfmAccount.find_by!(lookup_key: args.fetch(:username).downcase)
    puts JSON.pretty_generate({ account_id: account.id, username: account.username, ownership_verified: false,
      state: account.state, sync_enabled: account.sync_enabled, observations: account.scrobbles.count,
      source_deliveries: SourceDelivery.where(lastfm_account: account).group(:classification).count,
      issues: IngestionIssue.where(lastfm_account: account).group(:kind).count,
      next_poll_at: account.next_poll_at, last_successful_poll_at: account.last_successful_poll_at,
      latest_scrobble_at: account.latest_scrobble_at, synced_through: account.synced_through,
      failures: account.failure_count, last_error: account.last_error,
      recent_runs: account.import_runs.order(id: :desc).limit(20).map { |run| run.attributes.slice("id", "kind", "status", "actor_kind", "authorization_context", "lower_bound", "upper_bound", "next_page", "total_pages", "expected_count", "last_error", "retry_count", "retry_at") } })
  end
end
