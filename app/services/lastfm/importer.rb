module Lastfm
  # Trusted operator CLI compatibility entry point; uses the same durable importer.
  class Importer
    MAX_PAGES = 3

    def self.run!(username:, page_limit: MAX_PAGES)
      user = User.find_by!(lastfm_username: username)
      new(user, client: Clients::Lastfm.new(username: username)).run(page_limit: page_limit)
    end

    def initialize(user, client:)
      @user, @client = user, client
    end

    def run(page_limit: MAX_PAGES)
      run = @user.with_lock do
        @user.import_runs.where(status: %i[pending running failed]).order(:created_at).last ||
          @user.import_runs.create!(source_username: @user.lastfm_username, upper_bound: Time.current.to_i, status: :pending)
      end
      page_limit.times do
        HistoricalImporter.new(run, client: @client).page!
        break if run.reload.completed?
      end
      run
    end
  end
end
