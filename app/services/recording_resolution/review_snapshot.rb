module RecordingResolution
  class ReviewSnapshot
    VERSION = "manual-review-v1"

    def self.release_batch(snapshot:, ranking:, candidate_mbid:, feedback:, observation_ids:)
      { "version" => "manual-review-release-v1", "feedback" => feedback, "candidate_mbid" => candidate_mbid,
        "shown_at" => snapshot.fetch("shown_at"), "release" => snapshot.fetch("release"),
        "ranking" => ranking, "affected_observation_ids" => observation_ids,
        "affected_observation_count" => feedback == "selected" ? observation_ids.size : 0 }
    end

    def self.capture(assessment:, ranking:, feedback:, candidate_mbid:, affected_count:)
      return { "feedback" => feedback, "affected_observation_count" => affected_count } unless assessment

      {
        "version" => VERSION, "feedback" => feedback, "candidate_mbid" => candidate_mbid,
        "affected_observation_count" => affected_count,
        "assessment" => { "id" => assessment.id, "digest" => assessment.digest, "version" => assessment.version,
          "created_at" => assessment.created_at.utc.iso8601(6), "requests" => assessment.evidence["requests"] },
        "ranking" => ranking, "shortlist" => ranking.first(3).pluck("recording_mbid"),
        "recommended_mbid" => Ranking.recommended?(ranking) ? ranking.first.fetch("recording_mbid") : nil
      }.compact
    end
  end
end
