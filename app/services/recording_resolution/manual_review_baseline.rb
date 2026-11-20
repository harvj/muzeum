module RecordingResolution
  class ManualReviewBaseline
    def self.call(listener, before_id: nil)
      raise ArgumentError, "Manual review baseline is for disposable data" if Rails.env.production?

      history = Ledger.history(listener).where(user_id: listener.id, actor: "listener")
      page = history.order(id: :desc)
      page = page.where(id: ...before_id) if before_id
      decisions = page.limit(Workspace::PAGE + 1).to_a
      has_more = decisions.length > Workspace::PAGE
      decisions.pop if has_more

      recordings = Recording.where(id: decisions.filter_map(&:recording_id)).pluck(:id, :mbid).to_h
      superseded = history.where(predecessor_id: decisions.map(&:id)).pluck(:predecessor_id).to_set
      actions = Hash.new(0)
      comparisons = Hash.new(0)
      decisions.each do |decision|
        code = decision.evidence["reason_code"]
        action = { "deferred_review" => "deferred", "rejected_candidate" => "rejected" }.fetch(code, decision.mode)
        actions[action] += 1
        next unless action == "resolved"

        result = comparison(decision.evidence, recordings[decision.recording_id])
        comparisons[result] += 1
      end

      {
        "decision_events" => decisions.length, "superseded_events" => superseded.length,
        "actions" => actions.to_h, "recorded_ranking_comparisons" => comparisons.to_h,
        "next_before_id" => has_more ? decisions.last.id : nil
      }
    end

    def self.comparison(evidence, mbid)
      scores = evidence["candidate_scores"]
      return "no_recorded_ranking" unless evidence["scoring_version"].present? && scores.is_a?(Array) && scores.any?
      return "invalid_snapshot" if scores.any? { |entry| !entry.is_a?(Hash) || !entry["score"].is_a?(Integer) }
      return "no_recording_identifier" unless Clients::Musicbrainz::MBID.match?(mbid.to_s)

      selected = scores.find { |entry| entry["recording_mbid"] == mbid }
      return "selection_outside_ranked_set" unless selected

      highest = scores.map { |entry| entry.fetch("score") }.max
      return "selected_lower_rank" if selected.fetch("score") < highest

      scores.count { |entry| entry.fetch("score") == highest } == 1 ? "selected_unique_top" : "selected_among_top_tie"
    end
    private_class_method :comparison
  end
end
