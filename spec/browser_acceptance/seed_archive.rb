require "json"
require ENV.fetch("MUZEUM_BROWSER_FIXTURE")

abort "Disposable archive database required" unless ENV.fetch("DATABASE_URL").end_with?("/muzeum_browser_acceptance")
fixture = Object.new.extend(PublicProfileFixture).listening_profile_fixture
subject = JSON.parse(File.read(File.join(ENV.fetch("MUZEUM_BROWSER_WORK"), "identity.json"))).fetch("subject").to_s
fixture.fetch(:owner).update!(oidc_subject: subject)
abort "Unexpected fixture publication" if ListeningProfile.published.exists?(id: fixture.fetch(:profile).id)
