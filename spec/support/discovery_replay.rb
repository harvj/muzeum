module DiscoveryReplay
  class Session
    attr_reader :paths

    def initialize(fixture, example)
      @fixture = fixture
      @example = example
      @paths = []
    end

    def get(_provider, path, params:)
      @paths << path
      data = case path
      when "/ws/2/recording"
        candidates = @example.fetch("candidates")
        { "recordings" => candidates, "count" => candidates.size, "offset" => params.fetch(:offset) }
      when "/ws/2/release"
        { "releases" => @fixture.fetch("searches").fetch(@example.fetch("release_search")) }
      when %r{\A/ws/2/release/}
        @fixture.fetch("releases").fetch(path.split("/").last)
      when %r{\A/ws/2/recording/}
        @example["verified_recording"]
      else
        raise ArgumentError, "Uncaptured provider path"
      end
      data ? { "data" => block_given? ? yield(data) : data } : { "status" => 404 }
    end
  end

  def self.run(fixture, example, discover:)
    session = Session.new(fixture, example)
    surface = RecordingResolution::RealCorpusEvaluation::Observation.new(**example.fetch("surface").symbolize_keys)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    evidence = RecordingResolution::Evaluator.new(session, discogs: nil, workspace: true, discover:).call(surface, example.fetch("claims", {}))
    ranks = RecordingResolution::Ranking.call(surface, evidence, discovery: discover)
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000
    ids = ranks.pluck("recording_mbid")
    target = example.fetch("reviewed_mbid")
    recommendation = ids.first if RecordingResolution::Ranking.recommended?(ranks)
    { "surfaced" => ids.include?(target), "included_non_reference" => ids.count { |id| id != target },
      "correct_top" => ids.first == target && (ranks.one? || ranks.first.fetch("score") > ranks[1].fetch("score")),
      "recommendation" => recommendation ? (recommendation == target ? "correct" : "false_positive") : "withheld",
      "calls" => session.paths.size, "elapsed_ms" => elapsed.round(2), "paths" => session.paths, "ranking" => ranks }
  end
end
