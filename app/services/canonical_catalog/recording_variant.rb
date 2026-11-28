module CanonicalCatalog
  # Reviewed source descriptions keyed by exact recording MBID. They supply
  # presentation evidence only and never participate in identity or assignment.
  class RecordingVariant
    EVIDENCE = JSON.parse(Rails.root.join("config/catalog/recording_variants.json").read).freeze

    def self.for(mbid)
      EVIDENCE[mbid]
    end

    def self.related(mbid)
      variant = self.for(mbid)
      return {} unless variant

      EVIDENCE.except(mbid).select { |_, evidence| evidence.fetch("work_mbid") == variant.fetch("work_mbid") }
    end
  end
end
