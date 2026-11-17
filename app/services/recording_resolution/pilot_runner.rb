module RecordingResolution
  class PilotRunner
    MAX_GROUPS = 100
    MAX_OBSERVATIONS = 1_000
    BATCH = 100
    CLAIM_FIELDS = %w[artist_mbid album_mbid track_mbid].freeze

    def self.start!(archive_id:, upper_id:, live: false)
      raise ArgumentError, "Production pilots are disabled" if Rails.env.production?
      raise ArgumentError, "The upper observation must belong to this archive" unless
        Scrobble.exists?(id: upper_id, lastfm_account_id: archive_id)

      Pilot.create!(lastfm_account_id: archive_id, upper_id:, live:)
    end

    def self.dispatch!(pilot)
      raise ArgumentError, "Production pilots are disabled" if Rails.env.production?

      select!(pilot)
      now = Time.current
      Work.where(pilot_id: pilot.id).where(
        "(state = 'pending' AND due_at <= ?) OR (state = 'leased' AND lease_until <= ?)", now, now
      ).order(:id).limit(MAX_GROUPS).pluck(:id).each { |id| RecordingResolutionJob.perform_later(id) }
    end

    def self.select!(pilot)
      pilot.with_lock do
        return if pilot.selection_finished?

        remaining = MAX_OBSERVATIONS - pilot.observations_selected
        limit = [ remaining, BATCH ].min
        observations = Scrobble.where(lastfm_account_id: pilot.lastfm_account_id, id: (pilot.cursor + 1)..pilot.upper_id)
          .order(:id).limit(limit).to_a
        group_count = Work.where(pilot_id: pilot.id).count
        observations.each do |observation|
          break if group_count >= MAX_GROUPS

          surface = Ledger.attach!(observation)
          group = Group.create_or_find_by!(surface_id: surface.id, version: Ledger::VERSION,
            claims: observation.payload.slice(*CLAIM_FIELDS))
          unless Work.exists?(pilot_id: pilot.id, group_id: group.id)
            Work.create!(pilot_id: pilot.id, group_id: group.id, due_at: Time.current)
            group_count += 1
          end
          pilot.cursor = observation.id
          pilot.observations_selected += 1
        end

        pilot.selection_finished = group_count >= MAX_GROUPS || observations.size < limit ||
          pilot.cursor == pilot.upper_id || pilot.observations_selected == MAX_OBSERVATIONS
        pilot.save!
      end
    end
  end
end
