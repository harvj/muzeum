module Lastfm
  # Pure bounded parser: raw XML is retained separately; item hashes do not normalize text.
  class SourcePage
    attr_reader :meta, :items
    def initialize(raw)
      raw = raw.dup.force_encoding(Encoding::UTF_8)
      raise Clients::InvalidResponse unless raw.valid_encoding? && raw.bytesize <= 4.megabytes
      doc = Nokogiri::XML(raw) { |c| c.strict.nonet }
      raise Clients::InvalidResponse if doc.internal_subset
      root = doc.at_xpath("/lfm/recenttracks")
      raise Clients::InvalidResponse unless doc.at_xpath("/lfm")&.[]("status") == "ok" && root
      @meta = %w[page totalPages total].to_h do |name|
        value = root[name].to_s
        raise Clients::InvalidResponse unless value.match?(/\A\d+\z/)
        [ name, value.to_i ]
      end
      @meta["user"] = root["user"]
      nodes = root.xpath("./track")
      raise Clients::InvalidResponse if nodes.size > 201
      @items = nodes.each_with_index.map do |node, index|
        classification = if node["nowplaying"] == "true"
          "now_playing"
        elsif !node.at_xpath("date")
          "undated"
        end
        begin
          payload = RecentTracksParser.parse_track(node)
          classification ||= "malformed" if payload[:artist_name].blank? || payload[:track_name].blank? || payload[:played_at].nil?
        rescue Clients::InvalidResponse, RangeError, ArgumentError
          classification = "malformed"
          payload = {}
        end
        # Canonicalize a detached subtree: libxml otherwise walks the entire
        # containing page for every item. The canonical bytes are identical.
        evidence = Nokogiri::XML::Document.new
        evidence.root = node.dup(1, evidence)
        { position: index + 1, classification: classification, payload: payload,
          checksum: Digest::SHA256.hexdigest(evidence.canonicalize) }
      end
    rescue Nokogiri::XML::SyntaxError
      raise Clients::InvalidResponse
    end

    def self.fingerprint(account, payload)
      Digest::SHA256.hexdigest(JSON.generate([ account.identity_key, payload[:played_at].to_i,
        payload[:artist_name], payload[:album_name], payload[:track_name] ]))
    end
  end
end
