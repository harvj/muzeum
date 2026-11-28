module LeisureConfigurationsFixture
  def source_edition(edition)
    edition.merge("release-group" => { "id" => edition.fetch("release_group") },
      "media" => edition.fetch("media").map do |medium|
        tracks = medium.fetch("tracks").map do |track|
          track.merge("id" => track.fetch("track_mbid"),
            "recording" => { "id" => track.fetch("recording_mbid"), "title" => track.fetch("title") })
        end
        medium.merge("tracks" => tracks, "track-count" => tracks.size)
      end)
  end
end
