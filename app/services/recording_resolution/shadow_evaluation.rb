module RecordingResolution
  class ShadowEvaluation
    # Cases supply an independently reviewed MBID, or nil if identity remains unproved.
    # The returned journal is a simulation artifact. It never writes to the ledger.
    def self.call(cases)
      results = cases.map do |example|
        surface = Surface.new(example.fetch("surface"))
        ranks = Ranking.call(surface, example.fetch("evidence"))
        first, second = ranks
        proposal = Ranking.recommended?(ranks) ? first.fetch("recording_mbid") : nil
        reviewed = example.fetch("reviewed_mbid")
        outcome = if first.nil?
          "unsupported"
        elsif second && first["score"] == second["score"]
          "ambiguous"
        elsif proposal.nil?
          "review_required"
        elsif reviewed.nil?
          "unlabeled_proposal"
        elsif proposal == reviewed
          "correct"
        else
          "false_positive"
        end
        {
          "case" => example.fetch("case"), "reviewed_mbid" => reviewed, "proposed_mbid" => proposal,
          "outcome" => outcome, "ranking" => ranks
        }
      end
      { "scoring_version" => Ranking::VERSION, "outcomes" => results.map { |item| item.fetch("outcome") }.tally, "cases" => results }
    end
  end
end
