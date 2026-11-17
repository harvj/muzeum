module Lastfm
  class PageWriter
    def initialize(run, fetch, source, authorize: true)
      @run, @fetch, @source, @account = run, fetch, source, run.lastfm_account
      @authorize = authorize
    end

    # Caller holds the per-account advisory lock. No per-event database requests.
    def commit!(advance: true, legacy_page: nil)
      ImportRun.transaction do
        @account.lock!
        @run.lock!
        @account.authorize!(@run) if @authorize
        return if PageCommit.exists?(source_fetch_id: @fetch.id)
        items = @source.items
        valid = items.reject { |item| item[:classification] }
        valid.each do |item|
          time = item[:payload][:played_at].to_i
          raise SourceDrift unless time <= @fetch.upper_bound && (!@fetch.lower_bound || time >= @fetch.lower_bound)
          item[:fingerprint] = SourcePage.fingerprint(@account, item[:payload])
        end
        times = valid.map { |item| item[:payload][:played_at] }.uniq
        existing = @account.scrobbles.where(source_fingerprint: valid.map { |item| item[:fingerprint] }).pluck(:id, :source_fingerprint, :played_at)
        existing_seconds = @account.scrobbles.where(played_at: times).group(:played_at).count
        by_fingerprint = existing.to_h { |id, fp, time| [ fp, { id: id, time: time } ] }
        per_second = existing.group_by { |row| row[2].to_i }
        now = Time.current
        unless legacy_page
          rows = valid.uniq { |item| item[:fingerprint] }.reject { |item| by_fingerprint.key?(item[:fingerprint]) }.map do |item|
            { user_id: @account.archive_user_id, lastfm_account_id: @account.id, played_at: item[:payload][:played_at], payload: item[:payload],
              source_fingerprint: item[:fingerprint], created_at: now, updated_at: now }
          end
        end
        page = legacy_page || ImportPage.create!(import_run: @run, number: @fetch.phase == "boundary" ? -@fetch.id : @fetch.page_number,
          raw_body: @fetch.raw_body.dup.force_encoding(Encoding::UTF_8), checksum: @fetch.checksum)
        rows&.each { |row| row[:import_page_id] = page.id }
        inserted = rows.present? ? Scrobble.insert_all!(rows, returning: %w[id source_fingerprint]).rows.to_h { |id, fp| [ fp, id ] } : {}
        first_checksums = existing.empty? ? {} : SourceDelivery.where(scrobble_id: existing.map(&:first)).group(:scrobble_id).minimum(:id)
        checksums = SourceDelivery.where(id: first_checksums.values).pluck(:scrobble_id, :source_checksum).to_h
        incoming_seconds = valid.group_by { |item| item[:payload][:played_at].to_i }.transform_values { |group| group.map { |item| item[:fingerprint] }.uniq }
        seen = {}; counts = Hash.new(0)
        deliveries = items.map do |item|
          id = nil; classification = item[:classification]
          unless classification
            fp = item[:fingerprint]; prior = by_fingerprint[fp]; id = prior&.fetch(:id) || inserted[fp]
            raise SourceDrift unless id
            classification = prior || seen[fp] ? "repeat" : "inserted"
            classification = "legacy_first" if legacy_page && prior && !seen[fp] && !checksums[id]
            classification = "metadata_changed" if prior && checksums[id] && checksums[id] != item[:checksum]
            second = item[:payload][:played_at].to_i
            differing = existing_seconds.fetch(item[:payload][:played_at], 0) + incoming_seconds.fetch(second).size - per_second.fetch(second, []).size > 1
            counts["same_second"] += 1 if differing
            seen[fp] = true
          end
          counts[classification] += 1
          { source_fetch_id: @fetch.id, lastfm_account_id: @account.id, scrobble_id: id, position: item[:position],
            classification: classification, source_checksum: item[:checksum], created_at: now, updated_at: now }
        end
        SourceDelivery.insert_all!(deliveries) if deliveries.any?
        issue_rows = counts.reject { |kind, _| kind == "inserted" }.map do |kind, count|
          { lastfm_account_id: @account.id, import_run_id: @run.id, source_fetch_id: @fetch.id, kind: kind,
            details: { count: count }, created_at: now, updated_at: now }
        end
        IngestionIssue.insert_all!(issue_rows) if issue_rows.any?
        PageCommit.create!(source_fetch: @fetch, import_page: page, counts: counts)
        advance_run!(counts, inserted.size) if advance
      end
    end

    private

    def advance_run!(counts, inserted)
      complete = @source.meta["totalPages"].zero? || @fetch.page_number >= @source.meta["totalPages"]
      attributes = { status: :running, scrobbles_processed: @run.scrobbles_processed.to_i + inserted,
        received_count: @run.received_count + @source.items.size, repeated_count: @run.repeated_count + counts["repeat"] + counts["metadata_changed"],
        excluded_count: @run.excluded_count + counts["malformed"] + counts["undated"] + counts["now_playing"],
        last_success_at: Time.current, last_error: nil, retry_count: 0, retry_at: nil, failure_kind: nil }
      if @fetch.phase == "boundary"
        attributes.merge!(boundary_page: @run.boundary_page + 1, boundary_total: @source.meta["total"], boundary_done: complete)
      else
        attributes.merge!(next_page: @run.next_page + 1, expected_count: @source.meta["total"], total_pages: @source.meta["totalPages"])
        # Sweep every page boundary, including buckets longer than 200 items.
        oldest = @source.items.filter_map { |item| item[:classification].nil? && item[:payload][:played_at]&.to_i }.min
        attributes.merge!(boundary_second: oldest, boundary_done: oldest.nil?, boundary_page: 1, boundary_total: nil)
      end
      main_done = (attributes[:next_page] || @run.next_page) > (attributes[:total_pages] || @run.total_pages || 0)
      boundary_done = attributes.key?(:boundary_done) ? attributes[:boundary_done] : @run.boundary_done
      done = main_done && boundary_done
      attributes[:status] = :completed if done
      @run.update!(attributes)
      latest = @source.items.filter_map { |item| item[:classification].nil? && item[:payload][:played_at] }.max
      account_changes = { latest_scrobble_at: [ @account.latest_scrobble_at, latest ].compact.max,
        last_poll_at: Time.current, dispatch_until: nil, failure_count: 0, last_error: nil }
      if done
        active = @run.scrobbles_processed.to_i.positive? || account_changes[:latest_scrobble_at]&.after?(30.minutes.ago)
        interval = active ? 45 : [ @account.poll_interval * 2, 3600 ].min
        # Capacity pressure lengthens checks centrally; quiet archives wait longer.
        population = LastfmAccount.active.where(sync_enabled: true).count
        capacity_floor = (population * RequestBudget.interval * 3).ceil
        interval = [ interval, capacity_floor * (active ? 1 : 2) ].max.clamp(30, 604_800)
        account_changes.merge!(synced_through: [ @account.synced_through.to_i, @run.upper_bound ].max,
          last_successful_poll_at: Time.current, poll_interval: interval, next_poll_at: Time.current + interval)
      else
        account_changes[:next_poll_at] = Time.current + RequestBudget.interval
      end
      @account.update!(account_changes)
    end
  end
end
