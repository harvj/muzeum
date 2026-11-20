module RecordingResolution
  class Investigation
    KIND = "recording_investigation"
    VERSION = Ledger::VERSION

    def self.enabled?
      CatalogImport.worker_enabled? && (!Rails.env.production? || ENV["MUZEUM_RESOLUTION_INVESTIGATION"] == "1")
    end

    def initialize(listener, observation)
      @listener, @observation = listener, observation
      @claims = observation.payload.slice(*PilotRunner::CLAIM_FIELDS)
    end

    def group(surface)
      return unless surface

      Group.find_by(surface_id: surface.id, version: VERSION, claims: @claims)
    end

    def request(refresh: false, manual_mbid: nil)
      return unless self.class.enabled? || (refresh && CatalogImport.worker_enabled?)
      return if manual_mbid.nil? && @observation.payload.values_at("artist_name", "track_name").any?(&:blank?)

      created = nil
      request = ActiveRecord::Base.transaction do
        @listener.managed_archive_grants.lock.find_by!(lastfm_account_id: @observation.lastfm_account_id)
        surface = Ledger.attach!(@observation)
        group = Group.create_or_find_by!(surface_id: surface.id, version: VERSION, claims: @claims)
        previous = CatalogImport.latest(KIND, group.id)
        next previous if previous && (!refresh || previous.active?)

        created = CatalogImport.request!(KIND, group.id, "observation_id" => @observation.id,
          "requester_id" => @listener.id, "refresh" => refresh, "manual_mbid" => manual_mbid)
      end
      created&.dispatch
      request
    end
  end
end
