# bin/rails runner script/resolution_real_corpus.rb [--snapshots|--order-packets]
abort "Use a disposable Muzeum environment" if Rails.env.production?
abort "Expected no arguments, --snapshots or --order-packets" unless ARGV.empty? || [ %w[--snapshots], %w[--order-packets] ].include?(ARGV)

fixtures = Rails.root.join("spec/fixtures/recording_resolution/real_corpus")
catalog = JSON.parse(fixtures.join("catalog.json").read)
cases = JSON.parse(fixtures.join("cases.json").read)
evaluation = RecordingResolution::RealCorpusEvaluation.new(catalog:, cases:)
if ARGV == [ "--snapshots" ]
  puts JSON.pretty_generate(evaluation.snapshots)
else
  abort "Frozen ranking or evidence drifted" unless JSON.parse(fixtures.join("snapshots.json").read) == evaluation.snapshots
  puts JSON.pretty_generate(ARGV == [ "--order-packets" ] ? evaluation.order_packets : evaluation.evaluate)
end
