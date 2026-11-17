# Run only against the existing application revision; reads stored evidence, no API calls.
require "digest"
require "set"
report = { audited_at: Time.current.utc.iso8601, revision: File.read("REVISION").strip }
ActiveRecord::Base.transaction(isolation: :repeatable_read) do
  connection = ActiveRecord::Base.connection
  connection.execute("SET TRANSACTION READ ONLY")
  report[:read_only] = connection.select_value("SHOW transaction_read_only")
  report[:counts] = { users: User.count, scrobbles: Scrobble.count, raw_pages: ImportPage.count,
    missing_fingerprint: Scrobble.where(source_fingerprint: nil).count,
    missing_raw_page: Scrobble.where(import_page_id: nil).count,
    distinct_fingerprints: Scrobble.distinct.count(:source_fingerprint) }
  report[:same_second] = connection.select_one("SELECT count(*) AS buckets, coalesce(sum(n),0) AS observations FROM (SELECT count(*) n FROM scrobbles GROUP BY user_id, played_at HAVING count(*)>1) s")
  digest = Digest::SHA256.new
  Scrobble.order(:id).find_in_batches(batch_size: 1000) do |batch|
    batch.each { |s| digest << JSON.generate([ s.id, s.user_id, s.played_at&.utc&.iso8601(6), s.payload, s.source_fingerprint, s.import_page_id ]) << "\n" }
  end
  report[:preserved_source_digest_v1] = digest.hexdigest
  report[:id_range] = [ Scrobble.minimum(:id), Scrobble.maximum(:id) ]
  report[:runs] = ImportRun.order(:id).map do |run|
    counts = Hash.new(0); seen = Set.new; pages = []; totals = Set.new; raw_digest = Digest::SHA256.new
    ImportPage.where(import_run_id: run.id).order(:number).find_each do |page|
      pages << page.number
      raw_digest << "#{page.id}:#{page.checksum}\n"
      counts[:bad_checksums] += 1 unless Digest::SHA256.hexdigest(page.raw_body) == page.checksum
      doc = Nokogiri::XML(page.raw_body) { |c| c.strict.nonet }
      root = doc.at_xpath('/lfm/recenttracks')
      totals << root['total']; counts[:metadata_mismatch] += 1 unless root['page'].to_i == page.number && root['totalPages'].to_i == run.total_pages
      fingerprints = Set.new
      doc.xpath('/lfm/recenttracks/track').each do |node|
        counts[:delivered] += 1
        if node['nowplaying'] == 'true'; counts[:now_playing] += 1; next; end
        date = node.at_xpath('date')&.[]('uts').to_s
        unless date.match?(/\A[0-9]+\z/) && date.to_i.positive?; counts[:malformed_or_undated] += 1; next; end
        tuple = [ run.source_username.downcase, date.to_i, node.at_xpath('artist')&.text, node.at_xpath('album')&.text, node.at_xpath('name')&.text ]
        fp = Digest::SHA256.hexdigest(JSON.generate(tuple))
        counts[:timestamped] += 1
        counts[:above_cutoff] += 1 if date.to_i > run.upper_bound
        counts[:exact_repeat_deliveries] += 1 unless seen.add?(fp)
        fingerprints << fp
      end
      archived = Scrobble.where(import_page_id: page.id).pluck(:source_fingerprint)
      counts[:archive_not_on_first_raw_page] += (archived - fingerprints.to_a).length
    end
    { id: run.id, status: run.status, actor_lineage_user_id: run.user_id, upper_bound: run.upper_bound,
      expected_count: run.expected_count, inserted: run.scrobbles_processed, total_pages: run.total_pages,
      next_page: run.next_page, last_error: run.last_error, last_success_at: run.last_success_at,
      stored_pages: pages.size, page_range: [ pages.min, pages.max ],
      missing_pages: run.total_pages ? ((1..run.total_pages).to_a - pages) : [],
      source_totals: totals.to_a, distinct_source_tuples: seen.size, evidence: counts,
      page_manifest_digest_v1: raw_digest.hexdigest }
  end
  report[:immutability_triggers] = connection.select_all("SELECT c.relname, t.tgname, t.tgenabled, md5(pg_get_functiondef(t.tgfoid)) AS function_md5 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE NOT t.tgisinternal AND c.relname IN ('scrobbles','import_pages') ORDER BY c.relname,t.tgname").to_a
end
puts JSON.pretty_generate(report)
