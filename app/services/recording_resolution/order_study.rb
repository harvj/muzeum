module RecordingResolution
  class OrderStudy
    VERSION = "counterbalanced-recording-review-v1"
    MAX_RESPONSES = 1_000

    def initialize(packets)
      @packets = packets.index_by { |packet| packet.fetch("packet") }
      @arms = packets.map { |packet| packet.fetch("variants").size }.reduce(1, :lcm)
      @fingerprint = Digest::SHA256.hexdigest(packets.to_json)
    end

    def form(arm)
      raise ArgumentError, "Invalid study arm" unless (0...@arms).cover?(arm)

      { "version" => VERSION, "packet_digest" => @fingerprint, "arm" => arm, "forms" => @packets.values.map do |packet|
        variants = packet.fetch("variants")
        packet.except("variants").merge("candidates" => variants.fetch(arm % variants.size))
      end }
    end

    def evaluate(responses)
      unless responses.is_a?(Array) && responses.size <= MAX_RESPONSES && responses.all?(Hash)
        raise ArgumentError, "Expected a bounded array of study ballots"
      end

      seen = Set.new
      arms = {}
      outcomes = Hash.new(0)
      strata = Hash.new { |hash, key| hash[key] = { "first" => [ 0, 0 ], "later" => [ 0, 0 ] } }
      responses.each do |response|
        reviewer, arm, packet, choice = response.values_at("reviewer", "arm", "packet", "choice")
        unless reviewer.is_a?(String) && /\A[a-z0-9-]{1,40}\z/.match?(reviewer) &&
            response["version"] == VERSION && response["packet_digest"] == @fingerprint &&
            seen.add?([ reviewer, packet ]) && (arms[reviewer] ||= arm) == arm
          raise ArgumentError, "Invalid, duplicate or inconsistent ballot"
        end
        issued = form(arm).fetch("forms").find { |row| row.fetch("packet") == packet }
        candidates = issued&.fetch("candidates")&.pluck("recording_mbid")
        raise ArgumentError, "Choice was not presented" unless candidates && (choice == "abstain" || candidates.include?(choice))

        outcomes[choice == "abstain" ? "abstained" : "selected"] += 1
        candidates.each_with_index do |id, position|
          exposure = strata[[ packet, id ]][position.zero? ? "first" : "later"]
          exposure[0] += 1
          exposure[1] += 1 if choice == id
        end
      end
      compared = strata.values.select { |row| row.values.all? { |exposures, _| exposures.positive? } }
      differences = compared.map do |row|
        row.fetch("first").reverse.reduce(:fdiv) - row.fetch("later").reverse.reduce(:fdiv)
      end
      { "version" => VERSION, "packet_digest" => @fingerprint, "arms" => @arms,
        "reviewers" => arms.size, "outcomes" => outcomes, "comparable_candidate_strata" => compared.size,
        "mean_first_position_rate_difference" => (differences.sum.fdiv(differences.size) if differences.any?) }.compact
    end
  end
end
