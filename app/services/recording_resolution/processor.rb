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
      discogs = Clients::Discogs.new(session, live: false) unless pilot.live
      evaluator = Evaluator.new(session, discogs:)
      evidence = evaluator.call(Surface.find(group.surface_id), group.claims)
      finish(token, group, evidence, session.provenance)
    rescue ProviderError => error
      retry_or_stop(token, error, group, session, evaluator&.evidence)
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
        assessment = record_assessment(group, evidence, provenance)
        @work.update!(state: "done", assessment_id: assessment.id, lease_token: nil, lease_until: nil, failure: nil)
      end
    end

    def record_assessment(group, evidence, provenance)
      digest = Digest::SHA256.hexdigest(canonical_json(evidence).to_json)
      Assessment.create_or_find_by!(group_id: group.id, version: Evaluator::VERSION, digest:) do |row|
        row.actor = "recording_resolution_worker"
        row.evidence = evidence.merge("requests" => provenance)
        row.suggested_recording_id = catalog_recording(evidence)&.id
      end
    end

    def catalog_recording(evidence)
      mbid = evidence["suggested_mbid"]
      return unless mbid

      recording = RecordingSourceDecision.resolve(mbid)
      recording if recording&.verified_release_membership?
    end

    def canonical_json(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical_json(item) }
      when Array then value.map { |item| canonical_json(item) }
      else value
      end
    end

    def retry_or_stop(token, error, group, session, evidence)
      @work.with_lock do
        return unless @work.lease_token == token && @work.lease_until&.future?

        attempts = @work.attempts + (error.deferred ? 0 : 1)
        failed = error.terminal || attempts >= MAX_FAILURES
        due_at = error.retry_at || ((2**attempts).seconds + rand(0..3).seconds).from_now
        unless error.deferred
          evidence ||= { "source_claims" => group.claims, "reasons" => [], "reason_details" => {} }
          code = error.terminal ? "provider_request_stopped" : "provider_temporarily_unavailable"
          context = session.current_request || { "provider" => "musicbrainz", "stage" => "configuration" }
          evidence["reasons"] << code
          evidence["reason_details"][code] = context.merge("message" => error.message, "retry_exhausted" => failed && !error.terminal)
          record_assessment(group, evidence, session.provenance)
        end
        @work.update!(state: failed ? "failed" : "pending", attempts:, due_at:,
          failure: error.message, lease_token: nil, lease_until: nil)
      end
    end
  end
end
