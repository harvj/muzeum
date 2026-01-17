require "rails_helper"

RSpec.describe RecordingSurface, type: :model do
  describe ".normalize" do
    it "downcases artist and track names" do
      key = described_class.normalize(
        "A Tribe Called Quest",
        "Beats, Rhymes, and Life",
        "The Hop"
      )

      expect(key).to eq("a tribe called quest||beats, rhymes, and life||the hop")
    end

    it "collapses excess whitespace" do
      key = described_class.normalize(
        "A   Tribe   Called   Quest ",
        "Beats, Rhymes,    and Life",
        "  The   Hop "
      )

      expect(key).to eq("a tribe called quest||beats, rhymes, and life||the hop")
    end

    it "preserves punctuation and parentheses" do
      key = described_class.normalize(
        "Band",
        "Foo",
        "Song Name (Garbage)"
      )

      expect(key).to eq("band||foo||song name (garbage)")
    end
  end
end
