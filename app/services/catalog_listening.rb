# Aggregates the effective observation relation supplied by the resolution ledger.
class CatalogListening
  RANGES = { "all" => nil, "year" => 1.year, "90d" => 90.days, "30d" => 30.days }.freeze
  GROUPINGS = { "years" => "year", "months" => "month", "days" => "day" }.freeze
  Stats = Data.define(:plays, :milliseconds, :known_durations, :last_played) do
    def +(other)
      self.class.new(plays + other.plays, milliseconds + other.milliseconds,
        known_durations + other.known_durations, [ last_played, other.last_played ].compact.max)
    end
  end
  EMPTY = Stats.new(0, 0, 0, nil)

  def initialize(plays)
    observations = plays.unscope(:select, :order).select(
      "scrobbles.id, scrobbles.played_at, effective_resolution.recording_id").distinct
    @plays = Scrobble.from(observations, :scrobbles).joins(
      "JOIN recordings listening_recordings ON listening_recordings.id = scrobbles.recording_id")
  end

  def total
    Stats.new(*@plays.pluck(Arel.sql(metrics)).first)
  end

  def by_recording
    id = Arel.sql("scrobbles.recording_id")
    @plays.group(id).pluck(id, Arel.sql(metrics)).to_h { |key, *values| [ key, Stats.new(*values) ] }
  end

  def timeline(range, grouping, now: Time.current)
    window = RANGES.fetch(range)
    unit = GROUPINGS.fetch(grouping)
    observations = @plays.where(played_at: ..now)
    observations = observations.where(played_at: (now - window)..now) if window

    bucket = Arel.sql("date_trunc('#{unit}', scrobbles.played_at)::date")
    observations.group(bucket).order(bucket).pluck(bucket, Arel.sql(metrics))
      .map { |date, *stats| [ date.to_date, Stats.new(*stats) ] }
  end

  private

  def metrics
    "COUNT(DISTINCT scrobbles.id), COALESCE(SUM(listening_recordings.duration_ms) FILTER " \
      "(WHERE listening_recordings.duration_ms > 0), 0), " \
      "COUNT(DISTINCT scrobbles.id) FILTER (WHERE listening_recordings.duration_ms > 0), MAX(scrobbles.played_at)"
  end
end
