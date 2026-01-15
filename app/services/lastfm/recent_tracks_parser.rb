require "nokogiri"

module Lastfm
  class RecentTracksParser
    def self.parse_meta(xml)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!

      root = doc.at("//recenttracks")

      {
        page: root["page"]&.to_i,
        per_page: root["perPage"]&.to_i,
        total_pages: root["totalPages"]&.to_i,
        user: root["user"]
      }
    end

    def self.parse_tracks(xml)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!

      doc.xpath("//recenttracks/track").map do |node|
        parse_track(node)
      end
    end

    def self.parse_track(node)
      {
        artist_name: node.at("artist")&.text&.strip,
        artist_mbid: blank_to_nil(node.at("artist")&.[]("mbid")),
        track_name: node.at("name")&.text&.strip,
        track_mbid: blank_to_nil(node.at("mbid")&.text),
        album_name: node.at("album")&.text&.strip,
        album_mbid: blank_to_nil(node.at("album")&.[]("mbid")),
        played_at: parse_played_at(node)
      }
    end

    def self.parse_played_at(node)
      date = node.at("date")
      return nil unless date

      Time.at(date["uts"].to_i).utc
    end

    def self.blank_to_nil(value)
      value.presence
    end
  end
end
