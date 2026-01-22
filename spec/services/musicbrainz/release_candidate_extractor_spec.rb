require "rails_helper"

RSpec.describe Musicbrainz::ReleaseCandidateExtractor do
  subject(:candidates) { described_class.call(recordings) }

  let(:recordings) do
    JSON.parse(
      File.read(
        Rails.root.join(
          "spec/fixtures/musicbrainz/recording_search/the_hop.json"
        )
      )
    )
  end

  describe "basic extraction" do
    it "returns one candidate per release group" do
      release_group_mbids = candidates.map(&:release_group_mbid)

      expect(release_group_mbids.uniq.size)
        .to eq(release_group_mbids.size)
    end

    it "returns the expected number of release candidates" do
      # Beats, Rhymes and Life
      # MTV Raps, Volume 3 (compilation)
      expect(candidates.size).to eq(2)
    end
  end

  describe "Beats, Rhymes and Life (album)" do
    let(:album_candidate) do
      candidates.find do |c|
        c.release_group_title == "Beats, Rhymes and Life"
      end
    end

    it "exists" do
      expect(album_candidate).to be_present
    end

    it "uses the album release group mbid as identity" do
      expect(album_candidate.release_group_mbid)
        .to eq("af2a22ae-15c9-3c73-9a35-7b4f503d8f7c")
    end

    it "selects a US release as the representative source" do
      expect(album_candidate.country).to eq("US")
    end

    it "selects the 1996-07-30 release as canonical" do
      expect(album_candidate.release_year).to eq(1996)
      expect(album_candidate.release_month).to eq(7)
      expect(album_candidate.release_day).to eq(30)
    end

    it "selects the correct representative release mbid" do
      # US release dated 1996-07-30
      expect(album_candidate.representative_release_mbid)
        .to eq("f906d3fd-7832-4018-a435-287cd9c50339")
    end

    it "does not select a Japanese release when non-JP releases exist" do
      jp_release_mbids = %w[
        d9f7dcc8-f35f-4837-bfb6-0c98f2260948
        54cfed7e-818d-415e-afaf-c6b7c621e870
        2aeedafe-275a-4175-bdac-f9343d98bc7a
      ]

      expect(jp_release_mbids)
        .not_to include(album_candidate.representative_release_mbid)
    end

    it "exposes track count from the representative release" do
      expect(album_candidate.track_count).to eq(15)
    end

    it "exposes formats from the representative release" do
      expect(album_candidate.formats).to include("12\" Vinyl")
    end
  end

  describe "MTV Raps, Volume 3 (compilation)" do
    let(:compilation_candidate) do
      candidates.find do |c|
        c.release_group_title == "MTV Raps, Volume 3"
      end
    end

    it "exists as a separate candidate" do
      expect(compilation_candidate).to be_present
    end

    it "has a different release group mbid than the album" do
      expect(compilation_candidate.release_group_mbid)
        .not_to eq(
          candidates.find { |c| c.release_group_title == "Beats, Rhymes and Life" }
                    .release_group_mbid
        )
    end

    it "is marked as a compilation via secondary types" do
      expect(compilation_candidate.secondary_types)
        .to include("Compilation")
    end

    it "selects the German release dated 1997-10-13" do
      expect(compilation_candidate.country).to eq("DE")
      expect(compilation_candidate.release_year).to eq(1997)
      expect(compilation_candidate.release_month).to eq(10)
      expect(compilation_candidate.release_day).to eq(13)
    end
  end
end
