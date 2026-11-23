module CanonicalCatalog
  class ResolutionPlan
    attr_reader :recording, :proposals, :observation_count

    def initialize(assessment, mbid, observation_count)
      @assessment = assessment
      @mbid = mbid
      @recording = Recording.find_by(mbid:)
      @observation_count = observation_count
      @proposals = ReviewedConstruction.resolution_choices(assessment, mbid, recording).sort_by do |choices|
        data = choices.first.construction.base.data
        [ data.dig("release-group", "primary-type") == "Album" ? 0 : 1, data.fetch("date"), data.fetch("id") ]
      end.first || []
    end

    def edition_id(proposal)
      proposal.construction.base.data.fetch("id")
    end

    def artists(proposal)
      construction = proposal.construction
      tracks = construction.base.slots + construction.additional_slots
      credits = [ *Array(construction.base.data["artist-credit"]), *tracks.flat_map { |slot| Array(slot.dig(:recording, "artist-credit")) } ]
      artists = credits.filter_map { |credit| credit["artist"] }.uniq { |artist| artist["id"] }
      existing = Artist.where(mbid: artists.pluck("id")).index_by(&:mbid)
      artists.map { |artist| [ artist, existing[artist["id"]] ] }
    end

    def fingerprint
      proposals_state = proposals.map do |proposal|
        construction = proposal.construction
        tracks = construction.base.slots + construction.additional_slots
        recordings = Recording.where(mbid: tracks.map { |track| track.dig(:recording, "id") }).order(:id).pluck(:id, :mbid)
        [ edition_id(proposal), ReviewedConstruction.head(proposal.existing),
          artists(proposal).map { |artist, existing| [ artist["id"], existing&.id ] }, recordings ]
      end
      memberships = recording.admitted_releases.where.not(catalog_verified_at: nil).reorder(:id).pluck(:id) if recording
      Digest::SHA256.hexdigest([ @assessment.id, @mbid, recording&.id, observation_count, memberships, proposals_state ].to_json)
    end
  end
end
