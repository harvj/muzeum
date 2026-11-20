module RecordingResolution
  class ReviewSnapshot
    VERSION = "manual-review-v1"

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
