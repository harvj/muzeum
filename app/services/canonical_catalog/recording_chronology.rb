module CanonicalCatalog
  module RecordingChronology
    ENTITY_TYPE = "RecordingChronology"

    def self.latest(recording)
      CatalogRevision.where(entity_type: ENTITY_TYPE, entity_id: recording.id).order(id: :desc).first
    end

    def self.record!(recording, user, start_date: nil, end_date: nil, source: nil, head: nil)
      start_date = start_date.to_s.strip.presence
      end_date = end_date.to_s.strip.presence
      source = source.to_s.strip
      start_range = date_range(start_date) if start_date
      end_range = date_range(end_date) if end_date
      if (end_range && (!start_range || end_range.end < start_range.begin)) || source.blank? || source.length > 1000
        raise ArgumentError, "Provide an ordered recording date or range and a source (up to 1,000 characters)."
      end

      recording.with_lock do
        if latest(recording)&.id.to_s != head.to_s
          raise ArgumentError, "The recording date changed. Review the latest date and try again."
        end
        request = CatalogImport.create!(kind: "recording_chronology", entity_id: recording.id, state: "imported",
          due_at: Time.current, context: { "reviewer_id" => user.id })
        CatalogRevision.create!(entity_type: ENTITY_TYPE, entity_id: recording.id, catalog_import: request,
          evidence: { "start_date" => start_date, "end_date" => end_date, "source" => source, "reviewer_id" => user.id })
      end
    end

    def self.date_range(value)
      raise ArgumentError, "Enter dates as YYYY, YYYY-MM, or YYYY-MM-DD." unless value.match?(/\A[1-9]\d{3}(?:-\d{2}){0,2}\z/)

      year, month, day = value.split("-").map(&:to_i)
      date = Date.new(year, month || 1, day || 1)
      date..(day ? date : (month ? date.end_of_month : date.end_of_year))
    rescue Date::Error
      raise ArgumentError, "Enter a valid recording date."
    end
    private_class_method :date_range
  end
end
