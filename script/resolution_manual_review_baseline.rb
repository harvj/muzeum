# bin/rails runner script/resolution_manual_review_baseline.rb LISTENER_ID [BEFORE_DECISION_ID]
abort "Use a disposable Muzeum environment" if Rails.env.production?
abort "Provide a fixture listener ID and optional paging cursor" unless (1..2).cover?(ARGV.length)

listener = User.find(Integer(ARGV.fetch(0), 10))
cursor = Integer(ARGV.fetch(1), 10) if ARGV.length == 2
puts JSON.pretty_generate(RecordingResolution::ManualReviewBaseline.call(listener, before_id: cursor))
