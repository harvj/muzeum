module ArtistGeographyFixture
  BOARDS = "69158f97-4c07-4c4e-baf8-4e4ab1ed666e"
  WILCO = "9e53f84d-ef44-4c16-9677-5fd4d78cbd7d"

  class Session
    attr_reader :fixture, :provenance

    def initialize
      @fixture = JSON.parse(Rails.root.join("spec/fixtures/artist_geography/wikimedia.json").read)
      @provenance = []
    end

    def get(provider, path, params:, **)
      @provenance << { "provider" => provider.to_s, "endpoint" => path, "retrieved_at" => Time.current.iso8601 }
      data = case provider
      when :musicbrainz
        mbid = path.split("/").last
        { "id" => mbid, "name" => "Boards of Canada", "country" => "GB",
          "relations" => [ { "type" => "wikidata", "url" => { "resource" => "https://www.wikidata.org/wiki/Q722778" } } ] }
      when :wikidata
        { "entities" => fixture.fetch("entities").slice(*params.fetch(:ids).split("|")) }
      when :commons
        fixture.fetch("commons")
      end
      { "data" => yield(data) }
    end
  end

  def artist_origin(mbid, entity, country, session: Session.new)
    CanonicalCatalog::ArtistGeography.new(Clients::Wikimedia.new(session)).call(mbid:, entity_id: entity,
      musicbrainz: { "id" => mbid, "country" => country, "wikidata_ids" => [ entity ] })
  end
end
