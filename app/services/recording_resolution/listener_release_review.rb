module RecordingResolution
  class ListenerReleaseReview
    PURPOSE = :listener_release_review

    def initialize(listener, observation, assessment)
      @listener = listener
      @observation = observation
      @assessment = assessment
    end

    def ranked(surface)
      evidence = @assessment.evidence
      candidates = Workspace.candidate_evidence(evidence)
      supported = {}
      candidates.group_by { |candidate| candidate.dig("local_release_context", "release_id") }.each do |release_id, rows|
        next unless release_id && (release = Release.find_by(id: release_id))

        tracklist = ReleaseTracklist.new(release)
        decision = tracklist.independently_confirmed(@listener, @observation.lastfm_account_id, excluding: rows.pluck("id"))
        next unless decision

        rows.each do |candidate|
          context = candidate.fetch("local_release_context")
          next unless context["revision_id"] == tracklist.revision.id

          supported[candidate.fetch("id")] = context.merge("independent_decision_id" => decision.id)
        end
      rescue ArgumentError
        next
      end
      return if supported.empty?

      decorated = candidates.map do |candidate|
        context = supported[candidate["id"]]
        context ? candidate.merge("local_release_context" => context) : candidate
      end
      verified = decorated.find { |candidate| candidate["id"] == evidence.dig("verified_recording", "id") }
      Ranking.call(surface, evidence.merge("verified_recording" => verified, "candidates" => decorated))
    end

    def token(ranking)
      verifier.generate({ "identity" => identity, "ranking" => ranking }, purpose: PURPOSE, expires_in: 20.minutes)
    end

    def read(token)
      data = verifier.verified(token.to_s, purpose: PURPOSE)
      raise ArgumentError, "Displayed evidence expired or changed" unless data && data.fetch("identity") == identity

      data.fetch("ranking")
    end

    private

    def identity
      [ @listener.id, @observation.id, @assessment.id, @assessment.digest ]
    end

    def verifier
      Rails.application.message_verifier(:listener_release_review)
    end
  end
end
