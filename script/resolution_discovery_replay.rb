# RAILS_ENV=test bin/rails runner script/resolution_discovery_replay.rb
abort "Use a disposable Muzeum environment" if Rails.env.production?
require Rails.root.join("spec/support/discovery_replay")

fixture = JSON.parse(Rails.root.join("spec/fixtures/recording_resolution/discovery/corpus.json").read)
report = fixture.fetch("cases").to_h do |example|
  [ example.fetch("id"), {
    "baseline" => DiscoveryReplay.run(fixture, example, discover: false),
    "discovery" => DiscoveryReplay.run(fixture, example, discover: true)
  } ]
end
puts JSON.pretty_generate("version" => fixture.fetch("version"), "cases" => report)
