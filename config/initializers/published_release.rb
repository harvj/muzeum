require Rails.root.join("lib/muzeum_published_release")

Rails.application.config.x.published_release_tag =
  MuzeumPublishedRelease.from_file(Rails.root.join(MuzeumPublishedRelease::FILENAME))
