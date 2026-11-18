module CanonicalCatalog
  class Store
    class Unverified < StandardError; end

    class << self
      def recording!(data)
        mbid = mbid!(data["id"])
        title = name!(data["title"])
        Recording.create_or_find_by!(mbid:) { |recording| recording.title = title }
      end

      def mbid!(value)
        raise Unverified, "Provider identity could not be verified" unless Clients::Musicbrainz::MBID.match?(value.to_s)

        value.downcase
      end

      def name!(value)
        raise Unverified, "Provider name or title is missing" unless value.is_a?(String) && value.present?

        value
      end
    end

    def initialize(request, session)
      @request = request
      @session = session
    end

    def recording(data, expected: self.class.mbid!(data["id"]))
      raise Unverified, "Recording identity changed" unless data["id"] == expected

      record = self.class.recording!(data)
      refresh(record, { "title" => data["title"], "duration_ms" => positive(data["length"]) },
        "artist_credit" => credit_evidence(data["artist-credit"]))
      attach_credits(record, data["artist-credit"], RecordingArtist, :recording)
      record
    end

    def artist(data)
      mbid = self.class.mbid!(data["id"])
      name = self.class.name!(data["name"])
      artist = Artist.create_or_find_by!(mbid:) { |row| row.name = name }
      refresh(artist, "name" => name, "country" => data["country"].presence)
      artist
    end

    def release(data, slots, comparison: {})
      edition = self.class.mbid!(data["id"])
      title = self.class.name!(data["title"])
      group = data.dig("release-group", "id")
      signature = slots.map { |slot| [ slot.fetch(:medium), slot.fetch(:position), slot.fetch(:recording).fetch("id") ] }
      evidence = { "edition_mbid" => edition, "release_group_mbid" => group, "track_count" => slots.size,
        "tracklist_digest" => Digest::SHA256.hexdigest(signature.to_json), "discogs" => comparison }
      release = Release.find_by(ingested_from_release_mbid: edition)
      unless release
        lock_collection(group) if group.present?
        release = Release.find_by(ingested_from_release_mbid: edition)
        equivalent = equivalent_release(title, group, signature, data["artist-credit"]) unless release || group.blank?
        if equivalent
          refresh(equivalent, {}, evidence.merge("equivalent_edition" => true))
          return equivalent
        end
      end
      release ||= Release.create_or_find_by!(ingested_from_release_mbid: edition) do |row|
        row.title = title
        row.release_group_mbid = group
        row.primary_type = primary_type(data)
        row.secondary_type = "live" if Array(data.dig("release-group", "secondary-types")).include?("Live")
      end
      release.lock!
      existing = release_signature(release)
      if existing.any? && existing != signature
        raise Unverified, "Provider track order or membership changed; existing collection kept for review"
      end

      year, month, day = data["date"].to_s[/\A\d{4}(?:-\d{2}){0,2}\z/].to_s.split("-").map(&:to_i)
      refresh(release, { "title" => title, "catalog_country" => data["country"],
        "release_year" => year, "release_month" => month, "release_day" => day },
        evidence.merge("artist_credit" => credit_evidence(data["artist-credit"])))
      attach_credits(release, data["artist-credit"], ReleaseArtist, :release)

      slots.each do |slot|
        track_recording = self.recording(slot.fetch(:recording))
        release.catalog_track_slots.find_or_create_by!(medium: slot.fetch(:medium), position: slot.fetch(:position)) do |row|
          row.assign_attributes(slot.except(:recording).merge(recording: track_recording))
        end
      end
      release.update!(catalog_verified_at: Time.current)
      release
    end

    private

    def lock_collection(group)
      Release.connection.execute(Release.sanitize_sql_array(
        [ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", "muzeum:catalog-release:#{group}" ]
      ))
    end

    def equivalent_release(title, group, signature, credits)
      artist_mbids = credit_evidence(credits).pluck("artist_mbid").uniq
      Release.where(title:, release_group_mbid: group).where.not(catalog_verified_at: nil).order(:id).find do |item|
        item.artists.order(Arel.sql("release_artists.position ASC NULLS LAST"), :id).pluck(:mbid) == artist_mbids &&
          release_signature(item).map(&:last) == signature.map(&:last)
      end
    end

    def release_signature(release)
      release.catalog_track_slots.order(:medium, :position).includes(:recording).map do |slot|
        [ slot.medium, slot.position, slot.recording.mbid ]
      end
    end

    def credit_evidence(credits)
      Array(credits).map do |credit|
        { "artist_mbid" => credit.dig("artist", "id"), "credited_name" => credit["name"], "join_phrase" => credit["joinphrase"] }
      end
    end

    def positive(value)
      value if value.is_a?(Integer) && value.positive?
    end

    def primary_type(data)
      return "compilation" if Array(data.dig("release-group", "secondary-types")).include?("Compilation")

      { "EP" => "ep", "Single" => "single" }.fetch(data.dig("release-group", "primary-type"), "album")
    end

    def attach_credits(entity, credits, join, association)
      unless credits.is_a?(Array) && credits.any?
        raise Unverified, "Provider artist credits are incomplete"
      end

      credits.each_with_index do |credit, index|
        credited_artist = artist(credit.fetch("artist"))
        join.create_or_find_by!(association => entity, artist: credited_artist) { |row| row.position = index }
      end
    end

    def refresh(entity, fields, provenance = {})
      entity.lock!
      history = CatalogRevision.where(entity_type: entity.class.name, entity_id: entity.id)
      return if history.exists?(catalog_import_id: @request.id)

      baseline = history.order(id: :desc).pick(:evidence)&.fetch("verified_fields", {}) || {}
      evidence = { "verified_fields" => baseline.dup, "changes" => {}, "conflicts" => {},
        "requests" => @session.provenance.dup }.merge(provenance)
      fields.each do |field, value|
        next if value.blank?

        old = entity[field]
        if old.nil? || old == value || (baseline.key?(field) && old == baseline[field])
          entity[field] = value
          evidence["verified_fields"][field] = value
          evidence["changes"][field] = [ old, value ] if old != value
        else
          evidence["conflicts"][field] = [ old, value ]
        end
      end
      entity.save! if entity.changed?
      CatalogRevision.create!(catalog_import: @request, entity_type: entity.class.name, entity_id: entity.id, evidence:)
    end
  end
end
