module RecordingResolution
  module DiscoveryTitle
    EDITION_SUFFIX = /\s+\((deluxe(?: edition)?|expanded(?: edition)?|anniversary edition|bonus track edition)\)\z/i

    def self.key(value)
      value.to_s.unicode_normalize.tr("‘’ʼ", "'''").downcase.squish
    end

    def self.match?(first, second)
      first.present? && second.present? && key(first) == key(second)
    end

    FEATURE_SUFFIX = /\s+(?:\((?:feat\.?|ft\.?|featuring)\s+([^()\[\]]+)\)|\[(?:feat\.?|ft\.?|featuring)\s+([^()\[\]]+)\]|(?:[-–—]\s+)?(?:feat\.?|ft\.?|featuring)\s+([^()\[\]]+))\s*\z/i

    def self.featured_credit(title)
      suffix = FEATURE_SUFFIX.match(title.to_s)
      return unless suffix && suffix.pre_match.strip.present?

      guest = suffix.captures.compact.first.strip
      [ suffix.pre_match.strip, guest ] if guest.present?
    end

    def self.recording_match?(observed, title, credits)
      return true if match?(observed, title)

      base, guest = featured_credit(observed)
      return false unless guest && credit_key(base).present? && credit_key(base) == credit_key(featured_credit(title)&.first || title)

      guest_key = credit_key(guest)
      guest_key.present? && Array(credits).drop(1).any? do |credit|
        [ credit["name"], credit.dig("artist", "name") ].any? { |name| credit_key(name) == guest_key }
      end
    end

    def self.alternate_titles(title)
      base = featured_credit(title)&.first || title.to_s
      qualifier = base.sub(/\s+[(\[][^()\[\]]+[)\]]\z/, "")
      subtitle = base.split(/:\s+|\s+[–—]\s+/, 2)
      [ credit_key(base), qualifier, *subtitle.reverse ].map(&:strip)
        .reject { |value| value.length < 3 || key(value) == key(title) }.uniq
    end

    def self.credit_key(name)
      key(name).gsub(/[^[:alnum:]]+/, " ").strip
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
