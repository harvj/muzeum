require "rails_helper"

RSpec.describe CatalogListening::Window do
  let(:now) { Time.utc(2024, 2, 29, 14) }

  def window(period, grouping: nil, start: nil, at: now)
    described_class.new(period:, grouping:, start:, now: at)
  end

  it "offers only compatible groupings and normalizes unsupported URLs" do
    expect(described_class::PERIODS.transform_values(&:last)).to eq(
      "all" => %w[years months], "3y" => %w[years months], "year" => %w[months days],
      "6m" => %w[months days], "90d" => %w[days], "30d" => %w[days]
    )
    described_class::PERIODS.each do |period, (_, allowed)|
      allowed.each { |grouping| expect(window(period, grouping:).grouping).to eq(grouping) }
      expect(window(period, grouping: "invalid").grouping).to eq(allowed.first)
    end
    expect(window("all", grouping: "days", start: "2024-01-01").query).to eq(range: "all", grouping: "years")
    expect(window("year", grouping: "years", start: "2024-02-30").query).to eq(range: "year", grouping: "months", start: "2024-01-01")
    expect(window("90d", grouping: "months", start: "2050-01-01").grouping).to eq("days")
  end

  it "uses whole calendar years and can move a three-year window by one year" do
    current = window("year", grouping: "days")
    expect([ current.first, current.last, current.previous, current.following ].map { |value| value&.iso8601 })
      .to eq([ "2024-01-01", "2024-12-31", "2023-01-01", nil ])
    expect((current.last - current.first + 1).to_i).to eq(366)
    old = window("year", start: "2023-04-12")
    expect([ old.first, old.last, old.following ].map(&:iso8601)).to eq(%w[2023-01-01 2023-12-31 2024-01-01])
    three = window("3y", start: "2020-06-30")
    expect([ three.first, three.last, three.previous, three.following ].map(&:iso8601))
      .to eq(%w[2020-01-01 2022-12-31 2019-01-01 2021-01-01])
  end

  it "uses six full months across unequal month lengths and year boundaries" do
    current = window("6m")
    expect([ current.first, current.last, current.previous ].map(&:iso8601))
      .to eq(%w[2023-09-01 2024-02-29 2023-03-01])
    old = window("6m", start: current.previous.iso8601)
    expect([ old.first, old.last, old.following ].map(&:iso8601)).to eq(%w[2023-03-01 2023-08-31 2023-09-01])
  end

  it "keeps day windows contiguous and preserves explicit URL dates when reloaded later" do
    %w[90d 30d].each do |period|
      current = window(period)
      expect((current.last - current.first + 1).to_i).to eq(period.to_i)
      old = window(period, start: current.previous.iso8601)
      expect(old.last + 1).to eq(current.first)
      expect(old.following).to eq(current.first)
      expect(window(period, start: current.first.iso8601, at: now + 5.days).last).to eq(current.last)
      expect(window(period, start: "2099-12-01").first).to eq(current.first)
      expect(current.following).to be_nil
    end
  end
end
