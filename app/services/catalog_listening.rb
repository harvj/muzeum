# Aggregates the effective observation relation supplied by the resolution ledger.
class CatalogListening
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

  def timeline(window)
    unit = GROUPINGS.fetch(window.grouping)
    observations = @plays.where(played_at: ..window.now)
    if window.historical?
      start_at = Time.utc(window.first.year, window.first.month, window.first.day)
      end_date = window.last + 1
      end_at = Time.utc(end_date.year, end_date.month, end_date.day)
      observations = observations.where(played_at: start_at...end_at)
    end

    bucket = Arel.sql("date_trunc('#{unit}', scrobbles.played_at)::date")
    totals = observations.group(bucket).pluck(bucket, Arel.sql(metrics))
      .to_h { |date, *stats| [ date.to_date, Stats.new(*stats) ] }
    return [] if totals.empty? && !window.historical?

    first, last = if window.historical?
      [ window.first, window.last ].map { |date| date.public_send("beginning_of_#{unit}").to_date }
    else
      totals.keys.minmax
    end
    points = []
    date = first
    while date <= last
      points << [ date, totals.fetch(date, EMPTY) ]
      date = date.advance("#{unit}s": 1)
    end
    points
  end

  private

  def metrics
    "COUNT(DISTINCT scrobbles.id), COALESCE(SUM(listening_recordings.duration_ms) FILTER " \
      "(WHERE listening_recordings.duration_ms > 0), 0), " \
      "COUNT(DISTINCT scrobbles.id) FILTER (WHERE listening_recordings.duration_ms > 0), MAX(scrobbles.played_at)"
  end
end
