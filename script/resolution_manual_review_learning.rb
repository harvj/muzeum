# bin/rails runner script/resolution_manual_review_learning.rb LISTENER_ID UTC_SPLIT_TIME
abort "Use a disposable Muzeum environment" if Rails.env.production?
abort "Provide the fixture listener ID and split time" unless ARGV.length == 2

listener = User.find(Integer(ARGV.fetch(0), 10))
puts JSON.pretty_generate(RecordingResolution::ManualReviewLearning.for_listener(listener, split_at: ARGV.fetch(1)))
