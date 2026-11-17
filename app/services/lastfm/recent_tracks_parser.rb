require "nokogiri"

module Lastfm
  class RecentTracksParser
    def self.parse(xml, no_tracks: false)
      doc = Nokogiri::XML(xml) { |config| config.strict.nonet }
      doc.remove_namespaces!

      root = doc.at("//recenttracks")
      raise Clients::InvalidResponse unless root && doc.at("/lfm")&.[]("status") == "ok"
      meta = {
        page: root["page"]&.to_i,
        per_page: root["perPage"]&.to_i,
        total_pages: root["totalPages"]&.to_i,
        total: root["total"]&.to_i,
        user: root["user"]
      }
      return meta if no_tracks

      {
        meta: meta,
        tracks: doc.xpath("//recenttracks/track").map { |n| parse_track(n) }
      }
    rescue Nokogiri::XML::SyntaxError
      raise Clients::InvalidResponse
    end

    def self.parse_track(node)
      {
        artist_name: node.at("artist")&.text,
        artist_mbid: blank_to_nil(node.at("artist")&.[]("mbid")),
        track_name: node.at("name")&.text,
        track_mbid: blank_to_nil(node.at("mbid")&.text),
        album_name: node.at("album")&.text,
        album_mbid: blank_to_nil(node.at("album")&.[]("mbid")),
        played_at: parse_played_at(node)
      }
    end

    def self.parse_played_at(node)
      date = node.at("date")
      return nil unless date

      value = date["uts"].to_s
      raise Clients::InvalidResponse unless value.match?(/\A[0-9]+\z/) && value.to_i.positive?
      Time.at(value.to_i).utc
    end

    def self.blank_to_nil(value)
      value.presence
    end
  end
end
