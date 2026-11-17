namespace :recording_resolution do
  desc "Create a bounded assessment-only pilot (fixture mode unless LIVE=authorized)"
  task start: :environment do
    live = ENV["LIVE"] == "authorized"
    abort "Use LIVE=authorized only for an operator-approved live pilot" if ENV["LIVE"].present? && !live

    Clients::Discogs.new(nil, live: true) if live

    pilot = RecordingResolution::PilotRunner.start!(
      archive_id: Integer(ENV.fetch("ARCHIVE_ID")), upper_id: Integer(ENV.fetch("UPPER_ID")), live:
    )
    puts "Resolution pilot #{pilot.id}"
  end

  desc "Select one bounded batch and dispatch due resolution work for PILOT_ID"
  task dispatch: :environment do
    abort "Enable the isolated resolution queue with MUZEUM_RESOLUTION_QUEUE=1" unless Rails.env.development? &&
      ENV["MUZEUM_RESOLUTION_QUEUE"] == "1"

    pilot = RecordingResolution::Pilot.find(Integer(ENV.fetch("PILOT_ID")))
    RecordingResolution::PilotRunner.dispatch!(pilot)
    puts pilot.reload.attributes.slice("id", "cursor", "selection_finished", "observations_selected",
      "musicbrainz_requests", "discogs_requests").to_json
    puts RecordingResolution::Work.where(pilot_id: pilot.id).group(:state).count.to_json
  end
end
