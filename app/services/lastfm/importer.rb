module Lastfm
  # Trusted operator CLI: source identity is an account, never a login name.
  class Importer
    MAX_PAGES = 3

    def self.run!(username:, page_limit: MAX_PAGES)
      account = LastfmAccount.find_by!(lookup_key: username.downcase)
      new(account, client: Clients::Lastfm.new(username: account.username)).run(page_limit: page_limit)
    end

    def initialize(source, client:)
      @account = source.is_a?(LastfmAccount) ? source : source.source_account
      @client = client
    end

    def run(page_limit: MAX_PAGES)
      run = @account.with_lock do
        @account.authorize!
        existing = @account.import_runs.where(status: %i[pending running paused failed]).order(:id).last
        if existing
          existing.update!(status: :pending, retry_at: nil, retry_count: 0)
          existing
        else
          lower = @account.synced_through && [ @account.synced_through - Scheduler::LOOKBACK, 1 ].max
          upper = Time.current.to_i - 5
          upper = [ upper, lower + Scheduler::WINDOW ].min if lower
          @account.import_runs.create!(user: @account.archive_user, source_username: @account.username,
            lower_bound: lower, upper_bound: upper, kind: lower ? "incremental" : "historical", actor_kind: "operator",
            authorization_context: { service: "approved-operator-cli-v1" })
        end
      end
      Integer(page_limit).clamp(1, 100).times do
        HistoricalImporter.new(run, client: @client).page!
        break if run.reload.completed?
      end
      run
    end
  end
end
