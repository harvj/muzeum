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

    def request(refresh: false, manual_mbid: nil, release_mbid: nil, provenance_mbid: nil, provenance_assessment_id: nil, reassessment: nil, automatic: false)
      return unless self.class.enabled? || (refresh && !automatic && CatalogImport.worker_enabled?)
      return if manual_mbid.nil? && @observation.payload.values_at("artist_name", "track_name").any?(&:blank?)

      created = nil
      request = ActiveRecord::Base.transaction do
        @listener.managed_archive_grants.lock.find_by!(lastfm_account_id: @observation.lastfm_account_id)
        surface = Ledger.attach!(@observation)
        group = Group.create_or_find_by!(surface_id: surface.id, version: VERSION, claims: @claims)
        if reassessment
          next unless reassessment.group_id == group.id
          latest = Assessment.where(group_id: group.id).order(id: :desc).first
          next if latest != reassessment || (automatic && latest.version == Assessment::INTERPRETATION_VERSION)
        end
        previous = CatalogImport.latest(KIND, group.id)
        if previous
          next previous unless refresh
          next previous if automatic && previous.context["reassessment_id"] == reassessment&.id && !previous.active?

          previous.with_lock do
            if previous.expired_investigation?
              previous.update!(state: "failed", failure: "Investigation expired before completion.",
                lease_token: nil, lease_until: nil)
            end
          end
          if previous.active?
            created = previous unless previous.investigation_queue_state
            next previous
          end
        end

        context = { "observation_id" => @observation.id, "requester_id" => @listener.id, "refresh" => refresh,
          "manual_mbid" => manual_mbid, "release_mbid" => release_mbid }
        context["reassessment_id"] = reassessment.id if reassessment
        if provenance_mbid
          context.merge!("provenance_mbid" => provenance_mbid, "provenance_assessment_id" => provenance_assessment_id)
        end
        created = CatalogImport.request!(KIND, group.id, context)
      end
      created&.dispatch
      request
    end
  end
end
