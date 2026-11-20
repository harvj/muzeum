module CanonicalCatalog
  class ArtistGeography
    ENTITY_TYPE = "ArtistGeography"
    CONSTITUENT_COUNTRY = "Q3336843"
    STATE_TYPES = %w[Q35657 Q107390].freeze
    ARTIST_PROPERTIES = %w[P434 P495 P740].freeze
    PLACE_PROPERTIES = %w[P17 P31 P41 P131 P297].freeze
    MAX_PLACES = 12
    MAX_STEPS = 4

    def initialize(client)
      @client = client
    end

    def call(mbid:, entity_id:, musicbrainz:)
      @places = {}
      @artist = @client.entities([ entity_id ], properties: ARTIST_PROPERTIES)[entity_id]
      @evidence = { "provider" => "wikidata", "policy" => "artist-geography-v1", "entity_id" => entity_id,
        "artist_mbid" => mbid, "musicbrainz" => musicbrainz, "artist" => @artist, "places" => @places }

      return outcome("unverified_identity") unless @artist && values(@artist, "P434").include?(mbid)

      formations = values(@artist, "P740")
      origins = values(@artist, "P495")
      retrieve_places(formations + origins)
      return outcome("conflicting") if formations.many? || origins.many?
      return outcome("incomplete") unless (formation = @places[formations.first])

      countries = values(formation, "P17")
      return outcome("conflicting") if countries.many? || (origins.any? && countries.any? && origins != countries)

      @country = @places[countries.first || origins.first]
      codes = @country && values(@country, "P297")
      if codes.present? && musicbrainz["country"].present? && !codes.include?(musicbrainz["country"])
        return outcome("conflicting")
      end

      ancestors = ancestors_of(formation)
      nations = ancestors.select { |place| values(place, "P31").include?(CONSTITUENT_COUNTRY) }
      return outcome("conflicting") if nations.many?

      origin = nations.first || formation
      return outcome("incomplete") unless formation["label"].present? && origin["label"].present?
      return outcome("conflicting") if nations.any? && @country && values(origin, "P17") != [ @country["id"] ]

      parents = ancestors.select { |place| values(place, "P31").intersect?(STATE_TYPES) }
      return outcome("conflicting") if parents.many?

      hierarchy = [ origin, *parents, @country ].compact.uniq { |place| place["id"] }
      @flags = fetch_flags([ *hierarchy, formation ])
      @evidence.merge("status" => "verified", "origin" => display(origin), "founding_location" => display(formation),
        "country" => display(@country), "hierarchy" => hierarchy.filter_map { |place| display(place) })
    end

    private

    def outcome(status)
      @evidence.merge("status" => status)
    end

    def retrieve_places(frontier)
      MAX_STEPS.times do
        ids = frontier.uniq.select { |id| Clients::Wikimedia::ENTITY.match?(id.to_s) && !@places.key?(id) }.first(MAX_PLACES - @places.size)
        break if ids.empty?

        fetched = @client.entities(ids, properties: PLACE_PROPERTIES)
        @places.merge!(ids.index_with { |id| fetched[id] })
        frontier = fetched.values.flat_map { |place| values(place, "P131") + values(place, "P17") }
      end
    end

    def ancestors_of(formation)
      seen = { formation.fetch("id") => true }
      frontier = [ formation ]
      MAX_STEPS.times.flat_map do
        frontier = frontier.flat_map { |place| values(place, "P131") }.uniq.filter_map do |id|
          next if seen[id]

          seen[id] = true
          @places[id]
        end
      end
    end

    def values(entity, property)
      return [] if Array(entity["truncated"]).include?(property)

      Array(entity.dig("claims", property)).reject { |row| row["rank"] == "deprecated" || row["ended"] }
        .pluck("value").compact.uniq
    end

    def fetch_flags(places)
      names = places.filter_map do |place|
        files = values(place, "P41")
        files.first if files.one?
      end
      @client.flags(names)
    rescue RecordingResolution::ProviderError => error
      raise if error.deferred

      @evidence["flag_status"] = "provider_unavailable"
      {}
    end

    def display(place)
      return unless place&.fetch("label", nil).present?

      files = values(place, "P41")
      asset = @flags[files.first] if files.one?
      place.slice("id", "label").merge("flag" => asset).compact
    end
  end
end
