module Lastfm
  # Operator-run, restartable additive evidence indexing. Never inserts/updates scrobbles.
  class LegacyProvenance
    def self.backfill!(limit: 100)
      completed = 0
      ImportPage.where.not(id: PageCommit.select(:import_page_id)).order(:id).limit(limit).each do |page|
        run = page.import_run
        raise AccountConflict unless run.lastfm_account && run.actor_kind == "legacy"
        SourceFetch.transaction do
          run.lastfm_account.lock!
          next if PageCommit.exists?(import_page_id: page.id)
          fetch = SourceFetch.create!(import_run: run, lastfm_account: run.lastfm_account,
            legacy_import_page_id: page.id, page_number: page.number, upper_bound: run.upper_bound,
            requested_at: page.created_at, outcome: "legacy_response", raw_body: page.raw_body, checksum: page.checksum,
            request_parameters: { page: page.number, to: run.upper_bound, limit: 200, timing: "page recorded_at; request time not retained" })
          source = SourcePage.new(page.raw_body)
          PageWriter.new(run, fetch, source, authorize: false).commit!(advance: false, legacy_page: page)
          completed += 1
        end
      end
      completed
    end
  end
end
