# Partial dates match only queries containing their entire supported interval.
# An unknown date is displayed as unknown and is never a date-filter match.
class EffectiveReleaseDate
  attr_reader :iso, :first_day, :last_day

  def initialize(source)
    match = /\A([0-9]{4})(?:-([0-9]{2})(?:-([0-9]{2}))?)?\z/.match(source.to_s)
    return unless match

    y, m, d = match.captures.map { |part| part&.to_i }
    return unless y.positive? && Date.valid_date?(y, m || 1, d || 1)

    @iso = source
    @first_day = Date.new(y, m || 1, d || 1)
    @last_day = if d
      @first_day
    elsif m
      @first_day.end_of_month
    else
      @first_day.end_of_year
    end
  end

  def self.for(release, configuration = nil)
    return new(configuration.source_date) if configuration

    parts = [ release.release_year, release.release_month, release.release_day ].take_while(&:present?)
    new(parts.each_with_index.map { |part, index| format(index.zero? ? "%04d" : "%02d", part) }.join("-"))
  end

  def within?(from: nil, through: nil)
    first_day && (!from || first_day >= from) && (!through || last_day <= through)
  end
end
