# bin/rails runner script/resolution_real_corpus.rb [--snapshots|--order-packets|--study-arm N|--study-results PATH]
abort "Use a disposable Muzeum environment" if Rails.env.production?
option, argument = ARGV
abort "Unexpected evaluation arguments" unless ARGV.empty? || (
  ARGV.one? && %w[--snapshots --order-packets].include?(option)
) || (ARGV.size == 2 && %w[--study-arm --study-results].include?(option))

fixtures = Rails.root.join("spec/fixtures/recording_resolution/real_corpus")
catalog = JSON.parse(fixtures.join("catalog.json").read)
cases = JSON.parse(fixtures.join("cases.json").read)
evaluation = RecordingResolution::RealCorpusEvaluation.new(catalog:, cases:)
if ARGV == [ "--snapshots" ]
  puts JSON.pretty_generate(evaluation.snapshots)
else
  abort "Frozen ranking or evidence drifted" unless JSON.parse(fixtures.join("snapshots.json").read) == evaluation.snapshots
  report = case option
  when "--order-packets" then evaluation.order_packets
  when "--study-arm" then RecordingResolution::OrderStudy.new(evaluation.order_packets).form(Integer(argument, 10))
  when "--study-results" then RecordingResolution::OrderStudy.new(evaluation.order_packets).evaluate(JSON.parse(File.read(argument)))
  else evaluation.evaluate
  end
  puts JSON.pretty_generate(report)
end
