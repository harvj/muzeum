# Synthetic-only runner: dedicated DATABASE_URL must use an explicitly named benchmark DB.
require "digest"
require "json"
require "rbconfig"
require "active_support/testing/time_helpers"
abort "Dedicated synthetic benchmark DB required" unless ActiveRecord::Base.connection_db_config.database.match?(/\Amuzeum_p12_bench_[abc][123]\z/)
implementation = Digest::SHA256.new
Dir["app/services/lastfm/*.rb", "app/models/{lastfm_account,import_run,source_fetch,source_delivery,ingestion_budget,ingestion_issue,page_commit}.rb", "db/migrate/20261117*.rb"].sort.each { |path| implementation << path << File.binread(path) }
Rails.logger.level = Logger::INFO
folder = Pathname(ENV.fetch("FIXTURE_DIR"))
manifest = JSON.parse(folder.join("manifest.json").read)
mode = ENV.fetch("BENCHMARK_MODE")
user = User.create!(lastfm_username: "synthetic", oidc_issuer: OidcClient::ISSUER, oidc_subject: "synthetic-benchmark")
account = user.source_account
raise "Unexpected existing data" unless Scrobble.count.zero?
class SyntheticProvider
  attr_reader :requests, :clock, :rate_wait, :retry_wait, :latency_wait
  def initialize(folder, manifest, paced: false)
    @folder, @manifest, @requests = folder, manifest, 0
    @paced = paced
    @clock = Time.current.to_f
    @rate_wait = @retry_wait = @latency_wait = 0.0
  end
  def recent_tracks(page:, to:, limit:, from: nil)
    if @paced
      loop do
        begin
          Lastfm::RequestBudget.acquire!(now: Time.at(@clock))
          break
        rescue Lastfm::Deferred => error
          @clock += error.wait + 0.000001
          @rate_wait += error.wait
        end
      end
      @clock += 0.2
      @latency_wait += 0.2
    end
    @requests += 1
    raise Clients::NetworkError, "synthetic transient outage" if @paced && (@requests % 100).zero?
    if from
      index = (from + 1 - @manifest.fetch("first_timestamp")) / 2100
      number = ((@manifest.fetch("count") - 1 - index) / 200) + 1
      doc = Nokogiri::XML(@folder.join(format("%05d.xml", number)).read)
      node = doc.xpath("//track").find { |track| track.at("date")["uts"].to_i == from + 1 }
      "<lfm status='ok'><recenttracks user='synthetic' page='1' totalPages='1' total='1'>#{node.to_xml}</recenttracks></lfm>"
    else
      @folder.join(format("%05d.xml", page)).read
    end
  end
  def wait_for_retry(seconds)
    @clock += seconds
    @retry_wait += seconds
  end
end
extend ActiveSupport::Testing::TimeHelpers if mode == "C"
provider = SyntheticProvider.new(folder, manifest, paced: mode == "C")
connection = ActiveRecord::Base.connection
settings = %w[server_version fsync synchronous_commit full_page_writes shared_buffers].to_h { |name| [ name, connection.select_value("SHOW #{name}") ] }
results = []
%w[cold replay].each do |phase|
  before_requests = provider.requests
  before_waits = [ provider.rate_wait, provider.latency_wait, provider.retry_wait ]
  run = account.import_runs.create!(user: user, source_username: "synthetic", upper_bound: manifest.fetch("last_timestamp") + 1,
    actor_kind: "operator", authorization_context: { synthetic_benchmark: true })
  query_count = 0; sql_seconds = 0.0; page_times = []; rss_samples = []; phases = Hash.new(0.0)
  subscription = ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |_name, started_at, finished_at, _id, event|
    query_count += 1 unless event[:cached]
    sql_seconds += finished_at - started_at
  end
  timing_subscription = ActiveSupport::Notifications.monotonic_subscribe(/\A(fetch|parse|commit)\.lastfm\z/) do |name, started_at, finished_at, *_|
    phases[name] += finished_at - started_at
  end
  before_wal = connection.select_value("SELECT pg_current_wal_lsn()")
  before_bytes = connection.select_value("SELECT pg_database_size(current_database())").to_i
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  if mode == "A"
    manifest.fetch("pages").times do |offset|
      number = offset + 1; tick = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw = folder.join(format("%05d.xml", number)).read
      items = JSON.parse(folder.join(format("%05d.json", number)).read, symbolize_names: true)
      items.each { |item| item[:payload][:played_at] = Time.at(item[:payload][:played_at]).utc }
      source = Struct.new(:items, :meta).new(items, { "page" => number, "totalPages" => manifest.fetch("pages"), "total" => manifest.fetch("count") })
      fetch = SourceFetch.create!(lastfm_account: account, import_run: run, page_number: number, upper_bound: run.upper_bound,
        requested_at: Time.current, outcome: "synthetic_prebuilt", raw_body: raw, checksum: Digest::SHA256.hexdigest(raw))
      Lastfm::PageWriter.new(run, fetch, source).commit!
      page_times << Process.clock_gettime(Process::CLOCK_MONOTONIC) - tick
      rss_samples << [ offset * 200, `ps -o rss= -p #{Process.pid}`.to_i ] if offset % 125 == 0
    end
    run.update!(status: :paused) # A measures writes/checkpoints, not provider boundary completeness.
  else
    until run.reload.completed?
      tick = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        travel_to(Time.at(provider.clock), with_usec: true) if mode == "C"
        Lastfm::HistoricalImporter.new(run, client: provider).page!
      rescue Clients::NetworkError => error
        raise unless mode == "C"
        Lastfm::Scheduler.failure!(run, error)
        provider.wait_for_retry([ run.retry_at.to_f - provider.clock, 0 ].max + 0.001)
        travel_to(Time.at(provider.clock), with_usec: true)
        run.update!(status: :pending)
      end
      page_times << Process.clock_gettime(Process::CLOCK_MONOTONIC) - tick
      rss_samples << [ run.scrobbles_processed.to_i, `ps -o rss= -p #{Process.pid}`.to_i ] if page_times.size % 250 == 0
    end
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  ActiveSupport::Notifications.unsubscribe(subscription)
  ActiveSupport::Notifications.unsubscribe(timing_subscription)
  digest = Digest::SHA256.new; cursor = Time.at(0); cursor_id = 0
  loop do
    rows = Scrobble.where("(played_at,id) > (?,?)", cursor, cursor_id).order(:played_at, :id).limit(1000).pluck(:id, :played_at, :source_fingerprint)
    break if rows.empty?
    rows.each { |id, time, fp| digest << fp << "\n"; cursor, cursor_id = time, id }
  end
  raise "Independent manifest mismatch" unless digest.hexdigest == manifest.fetch("ordered_fingerprint_sha256") && Scrobble.count == manifest.fetch("count")
  raise "Canonical writes detected" unless Recording.count.zero? && RecordingSurface.count.zero?
  sorted = page_times.sort
  lookup = []
  30.times do
    tick = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    account.scrobbles.where("played_at < ?", Time.at(manifest.fetch("last_timestamp") - 50_000)).order(played_at: :desc, id: :desc).limit(100).pluck(:id, :played_at, :payload)
    lookup << Process.clock_gettime(Process::CLOCK_MONOTONIC) - tick
  end
  results << { phase: phase, mode: mode, seconds: elapsed, observations_per_second: manifest.fetch("count") / elapsed,
    new_scrobbles: run.scrobbles_processed, queries: query_count, sql_seconds: sql_seconds, phase_seconds: phases,
    cluster_wal_bytes: connection.select_value("SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), #{connection.quote(before_wal)})").to_i, statements_per_main_page: query_count.to_f / manifest.fetch("pages"),
    page_p50_seconds: sorted[(sorted.size * 0.5).floor], page_p95_seconds: sorted[(sorted.size * 0.95).floor],
    rss_at_validation_kib: `ps -o rss= -p #{Process.pid}`.to_i, rss_samples: rss_samples,
    database_growth_bytes: connection.select_value("SELECT pg_database_size(current_database())").to_i - before_bytes,
    verified_fingerprint_digest: digest.hexdigest, lookup_p95_seconds: lookup.sort[28], provider_requests: provider.requests - before_requests, virtual_rate_wait_seconds: provider.rate_wait - before_waits[0], virtual_latency_seconds: provider.latency_wait - before_waits[1], virtual_retry_seconds: provider.retry_wait - before_waits[2] }
  puts JSON.generate(results.last)
end
explain = connection.select_values("EXPLAIN (ANALYZE, BUFFERS) SELECT id,played_at,payload FROM scrobbles WHERE lastfm_account_id=#{account.id} AND played_at < '2020-01-01' ORDER BY played_at DESC,id DESC LIMIT 100")
output = { implementation_sha256: implementation.hexdigest, runtime: RUBY_DESCRIPTION, platform: RbConfig::CONFIG["host"], settings: settings, database: connection.current_database,
  manifest_digest: manifest.fetch("ordered_fingerprint_sha256"), results: results, explain: explain }
File.write(ENV.fetch("RESULT_PATH"), JSON.pretty_generate(output) + "\n")
