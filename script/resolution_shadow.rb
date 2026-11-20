# Run with bin/rails runner script/resolution_shadow.rb path/to/reviewed-cases.json
abort "Provide one reviewed JSON case file" unless ARGV.one?
cases = JSON.parse(File.read(ARGV.fetch(0)))
puts JSON.pretty_generate(RecordingResolution::ShadowEvaluation.call(cases))
