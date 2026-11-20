module Clients
  class Wikimedia
    ENTITY = /\AQ[1-9][0-9]{0,11}\z/
    FILE_NAME = /\A[^\/\\\[\]{}|#<>[:cntrl:]]{1,200}\.(?:svg|png)\z/i

    def initialize(session)
      @session = session
    end

    def entities(ids, properties:)
      ids = Array(ids).uniq
      return {} if ids.empty?
      raise ArgumentError, "Invalid Wikidata identifiers" unless ids.size <= 12 && ids.all? { |id| ENTITY.match?(id) }

      @session.get(:wikidata, "/w/api.php", params: { action: "wbgetentities", ids: ids.sort.join("|"),
        props: "claims|labels|info", languages: "en", maxlag: 5, format: "json" }, projection: properties.sort.join(",")) do |data|
        entities = data.fetch("entities")
        ids.index_with do |id|
          entity = entities[id]
          next unless entity && entity["id"] == id && !entity.key?("missing")

          selected = entity.fetch("claims", {}).slice(*properties)
          claims = selected.transform_values do |statements|
            statements.first(32).map do |statement|
              value = statement.dig("mainsnak", "datavalue", "value")
              { "id" => statement["id"], "rank" => statement["rank"], "value" => value.is_a?(Hash) && value.key?("id") ? value["id"] : value,
                "snaktype" => statement.dig("mainsnak", "snaktype"), "ended" => statement.fetch("qualifiers", {}).key?("P582"),
                "qualifiers" => statement.fetch("qualifiers", {}).slice("P580", "P582", "P1810"),
                "references" => Array(statement["references"]).first(4).pluck("hash") }
            end
          end
          { "id" => entity["id"], "label" => entity.dig("labels", "en", "value"), "revision" => entity["lastrevid"], "claims" => claims,
            "truncated" => selected.select { |_, rows| rows.size > 32 }.keys }
        end.compact
      end.fetch("data", {})
    end

    def flags(files)
      names = files.select { |file| FILE_NAME.match?(file.to_s) }.uniq.sort
      return {} if names.empty?

      @session.get(:commons, "/w/api.php", params: { action: "query", prop: "imageinfo", titles: names.map { |name| "File:#{name}" }.join("|"),
        iiprop: "url|mime|size|extmetadata", iiextmetadatafilter: "LicenseShortName|LicenseUrl|Artist|AttributionRequired",
        maxlag: 5, format: "json", formatversion: 2 }) do |data|
        Array(data.dig("query", "pages")).filter_map do |page|
          title = page["title"].to_s.delete_prefix("File:")
          info = page.dig("imageinfo", 0)
          next unless names.include?(title) && info && (asset = flag_metadata(info)).present?

          [ title, asset ]
        end.to_h
      end.fetch("data", {})
    end

    private

    def flag_metadata(info)
      asset = URI.parse(info.fetch("url"))
      source = URI.parse(info.fetch("descriptionurl"))
      return {} unless asset.scheme == "https" && asset.host == "upload.wikimedia.org" &&
        asset.path.start_with?("/wikipedia/commons/") && source.scheme == "https" && source.host == "commons.wikimedia.org" &&
        %w[image/svg+xml image/png].include?(info["mime"]) && (1..128.kilobytes).cover?(info["size"].to_i)

      metadata = info.fetch("extmetadata", {})
      license = metadata.dig("LicenseShortName", "value")
      return {} unless license.to_s.match?(/\A(?:Public domain|CC0|CC BY(?:-SA)? [1-4]\.0)\z/)

      author = ActionController::Base.helpers.strip_tags(metadata.dig("Artist", "value").to_s).squish.first(200)
      license_url = metadata.dig("LicenseUrl", "value").presence
      if license.start_with?("CC BY")
        return {} unless author.present? && license_url.to_s.match?(%r{\Ahttps://creativecommons\.org/licenses/(?:by|by-sa)/[1-4]\.0/\z})
      end

      asset.query = nil
      { "url" => asset.to_s, "source" => source.to_s, "license" => license, "author" => author.presence,
        "license_url" => (license_url if license.start_with?("CC BY")) }.compact
    rescue URI::InvalidURIError, KeyError
      {}
    end
  end
end
