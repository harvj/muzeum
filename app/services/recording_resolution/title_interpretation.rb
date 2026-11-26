module RecordingResolution
  # Search evidence only. Parsing never changes a source string or establishes identity.
  class TitleInterpretation
    VERSION = "recording-title-v1"
    MASTERING = /\A(?:(?<before>(?:19|20)\d{2})\s+)?(?:digitally\s+)?remaster(?:ed)?(?:\s+version)?(?:\s+(?<after>(?:19|20)\d{2}))?\z/i
    VERSION_WORDS = {
      "live" => /live(?:\s+(?:at|from|in|on)\s+.+)?/i,
      "instrumental" => /instrumental(?:\s+(?:mix|version))?/i,
      "acoustic" => /acoustic(?:\s+version)?/i,
      "demo" => /demo(?:\s+version)?/i,
      "remix" => /(?:.+\s+)?remix/i,
      "alternate take" => /alternate\s+take(?:\s+\d+)?/i,
      "edit" => /(?:(?:radio|single|album|extended)\s+)?edit/i,
      "re-recording" => /re[- ]?record(?:ing|ed)/i
    }.freeze

    def self.call(title)
      new(title.to_s).evidence
    end

    def self.descriptor(text)
      if (master = MASTERING.match(text))
        return { "kind" => "mastering", "name" => "remaster", "text" => text,
          "year" => (master[:before] || master[:after])&.to_i }.compact
      end

      version = VERSION_WORDS.find { |_, pattern| text.match?(/\A#{pattern}\z/) }&.first
      return unless version

      context = text[/\Alive\s+(?:at|from|in|on)\s+(.+)\z/i, 1] if version == "live"
      date = context&.[](/\b(?:19|20)\d{2}(?:-\d{2}-\d{2})?\b/)
      { "kind" => "version", "name" => version, "text" => text,
        "performance_context" => context, "reported_date" => date }.compact
    end

    def initialize(title)
      @title = title
    end

    def evidence
      tokens = @title.scan(/\([^()]+\)|\[[^\[\]]+\]|[^()\[\]]+/).flat_map do |span|
        if span.start_with?("(", "[")
          [ span[1...-1].strip ]
        else
          span.split(/\s+[-–—]\s+|:\s+/).map(&:strip).reject { |part| part.empty? || part.match?(/\A[-–—:]\z/) }
        end
      end
      classified = tokens.map { |part| self.class.descriptor(part) }
      return if classified.compact.empty? || classified.all?

      base_index = classified.index(nil)
      remaining = tokens.each_index.select { |index| !classified[index] && index != base_index }
      base = tokens.fetch(base_index)
      # Keep ambiguous title segments in the primary fallback. Only the explicit
      # qualifier spans are removed, preserving separators in the remaining text.
      residual = @title.dup
      classified.compact.each do |item|
        part = Regexp.escape(item.fetch("text"))
        residual = residual.sub(/\s*\(#{part}\)|\s*\[#{part}\]|\A\s*#{part}\s*(?:[-–—:]\s*)?|\s+[-–—]\s+#{part}(?=\s|\z)|:\s+#{part}(?=\s|\z)/i, "")
      end
      residual = residual.strip
      return if residual.blank? || residual == @title

      descriptors = classified.compact
      unknown = remaining.map { |index| tokens.fetch(index) }
      { "version" => VERSION, "original_title" => @title, "base_title" => residual,
        "descriptors" => descriptors, "unclassified" => unknown,
        "confidence" => unknown.empty? ? "explicit_qualifier" : "ambiguous_title_boundary",
        "basis" => "Recognized musical descriptors in delimited title segments",
        "alternatives" => [ @title, residual, (base if unknown.any?) ].compact.uniq }
    end

    def self.mastering_year(interpretation)
      Array(interpretation&.fetch("descriptors")).find { |item| item["kind"] == "mastering" }&.fetch("year", nil)
    end

    def self.mastering_only?(interpretation)
      interpretation && interpretation.fetch("descriptors").all? { |item| item["kind"] == "mastering" }
    end

    def self.recording_title_match?(interpretation, title)
      return false unless interpretation && interpretation["unclassified"].empty?

      candidate = call(title)
      DiscoveryTitle.match?(interpretation["base_title"], candidate&.fetch("base_title") || title)
    end
  end
end
