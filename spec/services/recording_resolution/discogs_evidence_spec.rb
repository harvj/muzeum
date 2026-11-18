require "rails_helper"

RSpec.describe RecordingResolution::DiscogsEvidence do
  let(:client) { instance_double(Clients::Discogs) }
  let(:surface) { RecordingResolution::Surface.new(artist: "Night Lines", album: "Night Drive", track: "Signals") }

  def stub_page(page, items, rows, reported_page: page)
    allow(client).to receive(:search_release).with(artist: surface.artist, title: surface.album, page:).and_return(
      "pagination" => { "page" => reported_page, "pages" => items.fdiv(2).ceil, "items" => items, "per_page" => 2 },
      "results" => rows)
  end

  def result(id, title: "Night Lines - Night Drive")
    { "id" => id, "title" => title }
  end

  def stub_release(id, track)
    allow(client).to receive(:release).with(id).and_return(
      "id" => id, "master_id" => 12, "title" => "Night Drive", "artists" => [ { "name" => "Night Lines" } ],
      "tracklist" => [ { "type_" => "index", "sub_tracks" => [ { "type_" => "track", "position" => "A1", "title" => track } ] } ])
  end

  def compare
    {}.tap { |evidence| described_class.new(client).compare(surface, nil, evidence) }
  end

  it "finds a later-page release and verifies it once across repeated IDs" do
    stub_page(1, 5, [ result(1, title: "Other"), result(2, title: "Other") ])
    stub_page(2, 5, [ result(3), result(4, title: "Other") ])
    stub_page(3, 5, [ result(3) ])
    stub_release(3, "Signals")

    evidence = compare
    expect(evidence).to include("status" => "corroborates", "matching_release_ids" => [ 3 ], "incomplete_reasons" => [])
    expect(evidence["releases"].first).to include("release_id" => 3, "master_id" => 12, "matching_positions" => [ "A1" ])
    expect(client).to have_received(:release).with(3).once
  end

  it "distinguishes a complete empty match from a capped search" do
    stub_page(1, 2, [ result(1, title: "Other"), result(2, title: "Other") ])
    expect(compare).to include("status" => "no_matching_release")

    3.times do |index|
      stub_page(index + 1, 8, [ result(1, title: "Other"), result(2, title: "Other") ])
    end
    expect(compare).to include("status" => "incomplete", "incomplete_reasons" => [ "search_page_limit" ])
  end

  it "does not claim absence when the provider repeats a page" do
    stub_page(1, 4, [ result(1, title: "Other"), result(2, title: "Other") ])
    stub_page(2, 4, [ result(1, title: "Other"), result(2, title: "Other") ], reported_page: 1)

    expect(compare).to include("status" => "incomplete", "incomplete_reasons" => [ "inconsistent_pagination" ])
  end

  it "records a malformed search result as incomplete without requesting an invalid release" do
    stub_page(1, 1, [ result(nil) ])

    expect(compare).to include("status" => "incomplete", "incomplete_reasons" => [ "invalid_search_results" ])
  end

  it "checks bounded cross-references and case variations in workspace mode" do
    stub_page(1, 2, [ result(3, title: "Night Lines - NIGHT DRIVE"), result(4, title: "Unrelated") ])
    stub_release(2, "Signals")
    stub_release(3, "Signals")
    edition = { "relations" => [ { "url" => { "resource" => "https://www.discogs.com/release/2-Night-Drive" } } ] }
    evidence = {}
    described_class.new(client, expanded: true).compare(surface, edition, evidence)

    expect(evidence).to include("status" => "corroborates", "cross_reference_ids" => [ 2 ], "matching_release_ids" => [ 2, 3 ])
    expect(evidence["releases"].pluck("status")).to eq(%w[corroborates corroborates])
  end

  it "preserves mixed edition evidence within the release-detail ceiling" do
    stub_page(1, 4, [ result(1), result(2) ])
    stub_page(2, 4, [ result(3), result(4) ])
    stub_release(1, "Signals")
    stub_release(2, "Other")
    stub_release(3, "Signals")

    evidence = compare
    expect(evidence).to include("status" => "mixed", "matching_release_ids" => [ 1, 2, 3, 4 ],
      "incomplete_reasons" => [ "release_detail_limit" ])
    expect(evidence["releases"].pluck("status")).to eq(%w[corroborates track_absent corroborates])
  end
end
