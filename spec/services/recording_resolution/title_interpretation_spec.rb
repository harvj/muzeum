require "rails_helper"

RSpec.describe RecordingResolution::TitleInterpretation do
  it "recognizes mastering qualifiers at delimited title boundaries" do
    [
      "Wear Me Down - 2012 Remaster",
      "Wear Me Down [2012 remastered version]",
      "Wear Me Down (Remastered 2012)",
      "2012 Remaster: Wear Me Down",
      "[2012 Remaster] Wear Me Down",
      "[2012 Remaster] - Wear Me Down"
    ].each do |title|
      interpretation = described_class.call(title)
      expect(interpretation).to include("original_title" => title, "base_title" => "Wear Me Down", "unclassified" => [])
      expect(interpretation.fetch("descriptors").sole).to include("kind" => "mastering", "name" => "remaster", "year" => 2012)
    end
  end

  it "retains live context, other versions, and unknown qualifiers without guessing their meaning" do
    title = "Song (Live at the Astoria, London 2007-07-02) [Instrumental] - 2012 Remaster (Blue)"
    interpretation = described_class.call(title)
    expect(interpretation).to include("base_title" => "Song (Blue)", "unclassified" => [ "Blue" ],
      "confidence" => "ambiguous_title_boundary", "alternatives" => [ title, "Song (Blue)", "Song" ])
    expect(interpretation.fetch("descriptors").first).to include("name" => "live",
      "performance_context" => "the Astoria, London 2007-07-02", "reported_place" => "the Astoria, London", "reported_date" => "2007-07-02")
    expect(interpretation.fetch("descriptors").pluck("name")).to eq([ "live", "instrumental", "remaster" ])
    expect(described_class.call("Song (Club Remix)").fetch("descriptors").sole).to include("name" => "remix")
    expect(described_class.recording_title_match?(interpretation, "Song")).to be(false)
  end

  it "reads the dated live disambiguation returned by MusicBrainz for the Blur fallback" do
    descriptor = described_class.descriptor("live, 1990-11-11: University of London Union, London, UK")
    expect(descriptor).to include("name" => "live", "reported_date" => "1990-11-11",
      "reported_place" => "University of London Union, London, UK")
  end

  it "does not shorten genuine or ambiguous titles without explicit musical evidence" do
    [ "Live Forever", "1979", "The Man - 2007", "Song (Blue)", "I Want You (She's So Heavy)", "Live" ].each do |title|
      expect(described_class.call(title)).to be_nil
    end
  end

  it "uses version context as ranking evidence without merging different IDs" do
    title = "Song (Live at the Astoria, London 2007)"
    surface = Struct.new(:track, :artist, :album).new(title, "Band", "Album")
    candidates = [ title, "Song (Live at the Forum, London 2008)", "Song (Instrumental)" ].map do |candidate_title|
      { "id" => SecureRandom.uuid, "title" => candidate_title, "artist-credit" => [ { "name" => "Band" } ] }
    end
    ranks = RecordingResolution::Ranking.call(surface, { "title_interpretation" => described_class.call(title), "candidates" => candidates })
    expect(ranks.pluck("recording_mbid")).to eq(candidates.pluck("id"))
    expect(ranks.map { |rank| rank.dig("inputs", "version", "state") }).to eq(%w[positive unavailable contradictory])
    expect(RecordingResolution::Ranking.recommended?(ranks)).to be_falsey
  end
end
