require "time"

module RecordingResolution
  class ManualReviewLearning
    VERSION = "pairwise-factor-sign-v1"

    def self.for_listener(listener, split_at:)
      raise ArgumentError, "Manual review learning is for disposable data" if Rails.env.production?

      rows = Ledger.history(listener).where(user_id: listener.id, actor: "listener").order(id: :desc)
        .limit(PilotRunner::MAX_OBSERVATIONS).map do |decision|
        {
          "id" => decision.id, "surface" => decision.surface_id,
          "stream" => [ decision.surface_id, decision.scrobble_id ],
          "at" => decision.created_at.utc.iso8601(6), "snapshot" => decision.evidence["review_snapshot"]
        }
      end
      call(rows, split_at:)
    end

    def self.call(rows, split_at:)
      new(rows, split_at).evaluate
    end

    def initialize(rows, split_at)
      @rows = rows.sort_by { |row| [ Time.iso8601(row.fetch("at")), row.fetch("id") ] }
      @split = Time.iso8601(split_at)
    end

    def evaluate
      before, after = @rows.partition { |row| Time.iso8601(row.fetch("at")) < @split }
      training = examples(before)
      held_out = examples(after)
      held_out_surfaces = held_out.map { |row| row.fetch("surface") }.to_set
      held_out_ids = held_out.flat_map { |row| ids(row) }.to_set
      eligible = training.reject do |row|
        held_out_surfaces.include?(row.fetch("surface")) || ids(row).any? { |id| held_out_ids.include?(id) }
      end
      weights = votes(eligible)
      {
        "learning_version" => VERSION, "split_at" => @split.utc.iso8601,
        "review_events" => @rows.map { |row| row.dig("snapshot", "feedback") || "legacy" }.tally,
        "training_examples" => eligible.length, "excluded_overlap" => training.length - eligible.length,
        "held_out_examples" => held_out.length, "factor_adjustments" => weights,
        "held_out_recommendation_outcomes" => held_out.map { |row| recommendation_outcome(row.fetch("snapshot")) }.tally,
        "baseline_top_choice" => agreement(held_out, {}),
        "shadow_top_choice" => agreement(held_out, weights)
      }
    end

    private

    def examples(rows)
      latest = {}
      rows.each do |row|
        snapshot = row["snapshot"]
        next if !snapshot || %w[deferred rejected].include?(snapshot["feedback"])

        latest[row.fetch("stream")] = row
      end
      latest.values.select do |row|
        snapshot = row.fetch("snapshot")
        shown = Array(snapshot["ranking"])
        taken_at = Time.iso8601(row.fetch("at"))
        snapshot["feedback"] == "selected" && snapshot["version"] == ReviewSnapshot::VERSION &&
          snapshot.dig("assessment", "created_at").present? &&
          Time.iso8601(snapshot.dig("assessment", "created_at")) <= taken_at &&
          Array(snapshot.dig("assessment", "requests")).all? { |request|
            !request["retrieved_at"] || Time.iso8601(request["retrieved_at"]) <= taken_at
          } && shown.many? && ids(row).include?(snapshot["candidate_mbid"])
      end
    end

    def ids(row)
      row.fetch("snapshot").fetch("ranking").pluck("recording_mbid")
    end

    def recommendation_outcome(snapshot)
      recommended = snapshot["recommended_mbid"]
      return "no_recommendation" if recommended.nil?

      recommended == snapshot["candidate_mbid"] ? "followed" : "overridden"
    end

    def features(rank)
      rank.fetch("inputs").filter_map do |name, input|
        "#{rank.fetch('version')}:#{name}=#{input.fetch('state')}" unless input["state"] == "unavailable"
      end.to_set
    end

    def votes(rows)
      counts = Hash.new(0)
      rows.each do |row|
        snapshot = row.fetch("snapshot")
        selected, alternatives = snapshot.fetch("ranking").partition { |rank| rank["recording_mbid"] == snapshot["candidate_mbid"] }
        chosen = features(selected.first)
        alternatives.each do |alternative|
          other = features(alternative)
          (chosen - other).each { |feature| counts[feature] += 1 }
          (other - chosen).each { |feature| counts[feature] -= 1 }
        end
      end
      counts.sort.to_h.transform_values { |count| count <=> 0 }.reject { |_, sign| sign.zero? }
    end

    def agreement(rows, weights)
      rows.count do |row|
        snapshot = row.fetch("snapshot")
        ranks = snapshot.fetch("ranking")
        scores = ranks.to_h do |rank|
          [ rank.fetch("recording_mbid"), rank.fetch("score") + features(rank).sum { |feature| weights.fetch(feature, 0) } ]
        end
        best = scores.values.max
        scores.values.count(best) == 1 && scores[snapshot.fetch("candidate_mbid")] == best
      end
    end
  end
end
