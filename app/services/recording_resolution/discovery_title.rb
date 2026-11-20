module RecordingResolution
  module DiscoveryTitle
    EDITION_SUFFIX = /\s+\((deluxe(?: edition)?|expanded(?: edition)?|anniversary edition|bonus track edition)\)\z/i

    def self.key(value)
      value.to_s.unicode_normalize.tr("‘’ʼ", "'''").downcase.squish
    end

    def self.match?(first, second)
      first.present? && second.present? && key(first) == key(second)
    end

    def self.album_base(value)
      value.to_s.sub(EDITION_SUFFIX, "")
    end

    def self.release_context?(album, release)
      match?(album, release["title"]) || match?(album_base(album), release["title"])
    end

    def self.displayed_edition?(album, release)
      title, qualifier = release.values_at("title", "disambiguation")
      match?(album, title) || (qualifier.present? && match?(album, "#{title} (#{qualifier})"))
    end
  end
end
