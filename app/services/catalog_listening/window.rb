class CatalogListening::Window
  PERIODS = {
    "all" => [ "All", %w[years months] ],
    "3y" => [ "3y", %w[years months] ],
    "year" => [ "Year", %w[months days] ],
    "6m" => [ "6m", %w[months days] ],
    "90d" => [ "90d", %w[days] ],
    "30d" => [ "30d", %w[days] ]
  }.freeze

  attr_reader :period, :grouping, :first, :last, :now

  def initialize(period:, grouping:, start: nil, now: Time.current)
    @now = now
    @period = PERIODS.key?(period) ? period : "all"
    @grouping = groupings.include?(grouping) ? grouping : groupings.first
    return unless historical?

    @current_start = default_start(now.utc.to_date)
    requested = parse_start(start)
    @first = requested ? [ align(requested), @current_start ].min : @current_start
    @last = case @period
    when "3y" then @first.advance(years: 3) - 1
    when "year" then @first.end_of_year
    when "6m" then @first.advance(months: 6) - 1
    else @first + days - 1
    end
  end

  def groupings = PERIODS.fetch(period).last
  def historical? = period != "all"

  def previous
    date = shift(-1)
    date if date.year.positive?
  end

  def following
    [ shift(1), @current_start ].min if first < @current_start
  end

  def query
    { range: period, grouping:, start: first&.iso8601 }.compact
  end

  private

  def parse_start(value)
    return unless value.is_a?(String) && /\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/.match?(value)

    date = Date.iso8601(value, Date::GREGORIAN)
    date if date.year.positive?
  rescue Date::Error
    nil
  end

  def default_start(today)
    case period
    when "3y" then today.beginning_of_year.advance(years: -2)
    when "year" then today.beginning_of_year
    when "6m" then today.beginning_of_month.advance(months: -5)
    else today - (days - 1)
    end
  end

  def align(date)
    case period
    when "3y", "year" then date.beginning_of_year
    when "6m" then date.beginning_of_month
    else date
    end
  end

  def shift(direction)
    case period
    when "3y", "year" then first.advance(years: direction)
    when "6m" then first.advance(months: direction * 6)
    else first + direction * days
    end
  end

  def days = period == "90d" ? 90 : 30
end
