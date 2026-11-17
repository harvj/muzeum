module RecordingResolution
  class Processor
    MAX_FAILURES = 5

    def initialize(work, fixture: nil)
      @work, @fixture = work, fixture
    end

    def call
      return if Rails.env.production?

      token = claim
      return unless token

      pilot = Pilot.find(@work.pilot_id)
      group = Group.find(@work.group_id)
      session = ProviderSession.new(@work, token, fixture: @fixture || FixtureTransport.new)
      discogs = Clients::Discogs.new(session, live: pilot.live)
      evidence = Evaluator.new(session, discogs:).call(Surface.find(group.surface_id), group.claims)
      finish(token, group, evidence, session.provenance)
    rescue ProviderError => error
      retry_or_stop(token, error)
    rescue ActiveRecord::StaleObjectError
      nil
    end

    private

    def claim
      @work.with_lock do
        claimable = (@work.state == "pending" && !@work.due_at.future?) ||
          (@work.state == "leased" && !@work.lease_until.future?)
        return unless claimable

        token = SecureRandom.uuid
        @work.update!(state: "leased", lease_token: token, lease_until: ProviderSession::LEASE.from_now)
        token
      end
    end

    def finish(token, group, evidence, provenance)
      @work.with_lock do
        ProviderSession.assert_lease!(@work, token)
        digest = Digest::SHA256.hexdigest(canonical_json(evidence).to_json)
        assessment = Assessment.create_or_find_by!(group_id: group.id, version: Evaluator::VERSION, digest:) do |row|
          row.actor = "recording_resolution_worker"
          row.evidence = evidence.merge("requests" => provenance)
          row.suggested_recording_id = catalog_recording(evidence)&.id
        end
        @work.update!(state: "done", assessment_id: assessment.id, lease_token: nil, lease_until: nil, failure: nil)
      end
    end

    def catalog_recording(evidence)
      return unless evidence["suggested_mbid"]

      verified = evidence.fetch("verified_recording")
      recording = Recording.create_or_find_by!(mbid: verified.fetch("id")) do |row|
        row.title = verified.fetch("title")
        row.duration_ms = verified["length"]
      end
      recording.lock!
      verified.fetch("artist-credit").each_with_index do |credit, position|
        source = credit.fetch("artist")
        artist = Artist.create_or_find_by!(mbid: source.fetch("id")) { |row| row.name = source.fetch("name") }
        RecordingArtist.create_or_find_by!(recording:, artist:) { |row| row.position = position }
      end
      recording
    end

    def canonical_json(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical_json(item) }
      when Array then value.map { |item| canonical_json(item) }
      else value
      end
    end

    def retry_or_stop(token, error)
      @work.with_lock do
        return unless @work.lease_token == token && @work.lease_until&.future?

        attempts = @work.attempts + (error.deferred ? 0 : 1)
        failed = error.terminal || attempts >= MAX_FAILURES
        due_at = error.retry_at || ((2**attempts).seconds + rand(0..3).seconds).from_now
        @work.update!(state: failed ? "failed" : "pending", attempts:, due_at:,
          failure: error.message, lease_token: nil, lease_until: nil)
      end
    end
  end
end
