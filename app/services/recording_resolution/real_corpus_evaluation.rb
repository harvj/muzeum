require "time"

module RecordingResolution
  class RealCorpusEvaluation
    VERSION = "public-catalog-replay-v2"
    MAX_CASES = 100
    Observation = Data.define(:artist, :album, :track)

    attr_reader :snapshots

    def initialize(catalog:, cases:)
      raise ArgumentError, "Use a bounded public-catalog corpus" unless (1..MAX_CASES).cover?(cases.size)
      raise ArgumentError, "Duplicate case" unless cases.pluck("id").uniq.size == cases.size

      @catalog = catalog
      @cases = cases
      @train, @held_out = cases.partition { |row| row["partition"] == "train" }
      unless @train.any? && @held_out.any? && @held_out.all? { |row| row["partition"] == "held_out" }
        raise ArgumentError, "Explicit training and held-out partitions required"
      end

      validate_partition!
      @snapshots = cases.to_h { |example| [ example.fetch("id"), snapshot(example) ] }
    end

    def evaluate
      captured = snapshots.values.map { |row| Time.iso8601(row.fetch("captured_at")) }.max
      split = captured + 10
      events = @cases.each_with_index.flat_map do |example, index|
        replay(example, index * 2, example["partition"] == "train" ? captured : split)
      end
      learning = ManualReviewLearning.call(events, split_at: split.iso8601)
      adjustments = learning.fetch("factor_adjustments")
      comparisons = @held_out.map { |example| compare(example, adjustments) }

      {
        "version" => VERSION, "rank_version" => Ranking::VERSION, "corpus_cases" => @cases.size,
        "training_cases" => @train.size, "held_out_cases" => @held_out.size,
        "learning" => learning,
        "baseline" => comparisons.map { |row| row.fetch("baseline") }.tally,
        "shadow" => comparisons.map { |row| row.fetch("shadow") }.tally,
        "baseline_top" => comparisons.map { |row| row.fetch("baseline_top") }.tally,
        "shadow_top" => comparisons.map { |row| row.fetch("shadow_top") }.tally,
        "discovery" => { "reviewed_cases" => comparisons.count { |row| row["reviewed_recording"] },
          "surfaced" => comparisons.count { |row| row["reviewed_candidate_surfaced"] },
          "missing" => comparisons.count { |row| row["reviewed_candidate_surfaced"] == false } },
        "offline_identifier_edition_conflict_probe" => comparisons.select { |row| row["checked_edition_conflict"] }.map do |row|
          row.slice("case", "baseline", "shadow")
        end,
        "simulated_corrections" => @cases.count { |row| row["initial_choice_ref"] && row["initial_choice_ref"] != row["reviewed_ref"] },
        "rank_order_controls" => order_controls,
        "cases" => comparisons
      }
    end

    def order_packets
      @held_out.group_by { |example| example.fetch("observation_group") }.values.filter_map.with_index do |examples, index|
        example = examples.find { |row| snapshots.fetch(row.fetch("id")).fetch("ranking").many? }
        next unless example

        candidates = snapshots.fetch(example.fetch("id")).fetch("ranking").map do |rank|
          {
            "recording_mbid" => rank.fetch("recording_mbid"), "catalog" => rank.fetch("catalog"),
            "evidence" => rank.fetch("inputs").transform_values { |input| input.except("weight") }
          }
        end.sort_by { |candidate| candidate.fetch("recording_mbid") }
        {
          "packet" => index + 1, "surface" => example.fetch("surface"),
          "variants" => candidates.each_index.map { |offset| candidates.rotate(offset) }
        }
      end
    end

    private

    def validate_partition!
      groups = @train.pluck("observation_group").to_set & @held_out.pluck("observation_group").to_set
      recordings = recording_ids(@train) & recording_ids(@held_out)
      raise ArgumentError, "Training and held-out observation groups overlap" if groups.any?
      raise ArgumentError, "Training and held-out recording IDs overlap" if recordings.any?
    end

    def recording_ids(cases)
      cases.flat_map do |example|
        refs = example.fetch("candidate_refs")
        raise ArgumentError, "Candidate pool outside bounds" unless (1..25).cover?(refs.size)

        %w[checked_slot_ref verified_identifier_ref initial_choice_ref].each do |field|
          ref = example[field]
          raise ArgumentError, "Reference outside candidate pool" if ref && !refs.include?(ref)
        end
        reviewed = example["reviewed_ref"]
        if reviewed && !refs.include?(reviewed) && !(example["partition"] == "held_out" && example["discovery_miss"] == true)
          raise ArgumentError, "Reference outside candidate pool"
        end
        (refs + [ reviewed ].compact).map { |ref| mbid(ref) }
      end.to_set
    end

    def reference(key)
      @catalog.fetch(key) if key
    end

    def mbid(key)
      reference(key)&.dig("recording", "id")
    end

    def snapshot(example)
      sources = example.fetch("candidate_refs").map { |ref| reference(ref).fetch("source").except("review_url") }.uniq
      candidates = example.fetch("candidate_refs").map { |ref| reference(ref).fetch("recording") }
      checked = reference(example["checked_slot_ref"])
      verified = reference(example["verified_identifier_ref"])
      source_claims = verified ? { "track_mbid" => verified.dig("recording", "id") } : {}
      evidence = { "candidates" => candidates, "source_claims" => source_claims,
        "verified_recording" => verified&.fetch("recording"),
        "edition" => checked&.fetch("release"), "slots" => checked ? [ checked.fetch("slot") ] : [] }
      ranks = Ranking.call(Observation.new(**example.fetch("surface").symbolize_keys), evidence)
      { "captured_at" => sources.pluck("retrieved_at").max, "sources" => sources, "evidence" => evidence,
        "ranking" => ranks, "recommended_mbid" => recommendation(ranks) }
    end

    def replay(example, sequence, time)
      return [] if example["discovery_miss"]

      captured = snapshots.fetch(example.fetch("id"))
      target = example["reviewed_ref"]
      initial = example["initial_choice_ref"]
      timeline = initial && initial != target ? [ initial, target ] : [ target ]
      timeline.map.with_index do |choice, index|
        {
          "id" => sequence + index, "surface" => example.fetch("observation_group"),
          "stream" => example.fetch("id"), "at" => (time + index).iso8601,
          "snapshot" => {
            "version" => ReviewSnapshot::VERSION, "candidate_mbid" => mbid(choice),
            "assessment" => { "created_at" => captured.fetch("captured_at"), "requests" => captured.fetch("sources") },
            "feedback" => choice ? "selected" : "deferred", "ranking" => captured.fetch("ranking"),
            "recommended_mbid" => captured["recommended_mbid"]
          }
        }
      end
    end

    def recommendation(ranks)
      ranks.first.fetch("recording_mbid") if Ranking.recommended?(ranks)
    end

    def compare(example, weights)
      ranks = snapshots.fetch(example.fetch("id")).fetch("ranking")
      shadow = ranks.map { |row| row.merge("score" => ManualReviewLearning.adjusted_score(row, weights)) }
        .sort_by { |row| [ -row.fetch("score"), row.fetch("recording_mbid") ] }
      target = mbid(example["reviewed_ref"])
      checked = mbid(example["checked_slot_ref"])
      verified = mbid(example["verified_identifier_ref"])
      {
        "case" => example.fetch("id"), "tags" => example.fetch("tags"),
        "reviewed_recording" => target, "baseline_recommendation" => recommendation(ranks),
        "shadow_recommendation" => recommendation(shadow),
        "reviewed_candidate_surfaced" => target && ranks.any? { |rank| rank["recording_mbid"] == target },
        "checked_edition_conflict" => !!(checked && verified && checked != verified),
        "baseline" => outcome(ranks, recommendation(ranks), target),
        "shadow" => outcome(shadow, recommendation(shadow), target),
        "baseline_top" => outcome(ranks, unique_top(ranks), target),
        "shadow_top" => outcome(shadow, unique_top(shadow), target)
      }
    end

    def unique_top(ranks)
      first, second = ranks
      first.fetch("recording_mbid") if first && (!second || first.fetch("score") > second.fetch("score"))
    end

    def outcome(ranks, proposed, target)
      return proposed ? "unsupported_on_ambiguous" : "ambiguous_abstention" unless target
      return proposed == target ? "correct" : "false_positive" if proposed
      return "reviewed_candidate_not_surfaced" unless ranks.any? { |rank| rank["recording_mbid"] == target }

      "abstained"
    end

    def order_controls
      labeled = @held_out.filter_map do |example|
        target = mbid(example["reviewed_ref"])
        displayed = snapshots.fetch(example.fetch("id")).fetch("ranking").pluck("recording_mbid")
        [ displayed, target ] if target && displayed.many? && displayed.include?(target)
      end
      {
        "eligible_cases" => labeled.size, "human_responses" => 0,
        "always_first_correct_original" => labeled.count { |displayed, target| displayed.first == target },
        "always_first_correct_reversed" => labeled.count { |displayed, target| displayed.last == target },
        "always_first_choices_changed" => labeled.count { |displayed, _| displayed.first != displayed.last },
        "identity_fixed_choices_changed" => 0
      }
    end
  end
end
