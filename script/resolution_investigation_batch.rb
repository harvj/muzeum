# bin/rails runner script/resolution_investigation_batch.rb LISTENER_ID LIMIT [BEFORE_COUNT BEFORE_ID]
abort "Batch investigation is limited to disposable environments" if Rails.env.production?
abort "Expected a listener ID, a limit, and an optional count/ID cursor" unless [ 2, 4 ].include?(ARGV.size) && ARGV.all? { |argument| argument.match?(/\A[1-9]\d*\z/) }
listener_id, limit, before_count, before_id = ARGV.map(&:to_i)
abort "Limit must be 1 through 10" unless (1..10).cover?(limit)
abort "Investigation worker is disabled" unless RecordingResolution::Investigation.enabled?

listener = User.find(listener_id)
workspace = RecordingResolution::Workspace.new(listener)
eligible = listener.managed_archive_grants.select(:lastfm_account_id)
before_id ||= 0
before_count ||= 0
queued = []
# Bound the number of queue pages scanned in each invocation. An optional run
# can be repeated safely because the investigation service reuses existing work.
3.times do
  rows = workspace.list(filter: "unresolved", before_id:, before_count:).first(RecordingResolution::Workspace::PAGE)
  break if rows.empty?

  observations = workspace.observations.where(lastfm_account_id: eligible, id: rows.map(&:first)).index_by(&:id)
  rows.each do |id, _, _, _, count, review|
    before_id, before_count = id, count
    next unless review.first == "Uninvestigated" && observations.key?(id)

    request = RecordingResolution::Investigation.new(listener, observations.fetch(id)).request
    queued << request.id if request
    break if queued.size >= limit
  end
  break if queued.size >= limit
end

puts JSON.generate("investigation_ids" => queued, "resume_cursor" => [ before_count, before_id ])
