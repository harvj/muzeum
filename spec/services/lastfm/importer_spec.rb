require "rails_helper"

RSpec.describe Lastfm::HistoricalImporter do
  let(:user) { User.create!(lastfm_username: "foo") }
  let(:client) { double("Lastfm client") }
  let(:run) { user.import_runs.create!(source_username: "foo", upper_bound: 2000) }
  def page(number, tracks, pages: 2, total: 2)
    "<lfm status='ok'><recenttracks user='foo' page='#{number}' totalPages='#{pages}' total='#{total}'>#{tracks}</recenttracks></lfm>"
  end
  def track(name, time)
    "<track><artist> Artist </artist><name>#{name}</name><album>Album</album><date uts='#{time}'>date</date></track>"
  end

  it "resumes after interruption and keeps raw pages with atomic checkpoints" do
    allow(client).to receive(:recent_tracks).with(page: 1, to: 2000, limit: 200).and_return(page(1, track("One", 1000)))
    described_class.new(run, client: client).page!
    expect(run.reload.next_page).to eq(2)
    expect(run.running?).to be(true)
    allow(client).to receive(:recent_tracks).with(page: 2, to: 2000, limit: 200).and_raise(Clients::NetworkError)
    expect { described_class.new(run, client: client).page! }.to raise_error(Clients::NetworkError)
    expect(run.reload.next_page).to eq(2)
    expect(Scrobble.count).to eq(1)
    allow(client).to receive(:recent_tracks).with(page: 2, to: 2000, limit: 200).and_return(page(2, track("Two", 500)))
    described_class.new(run.reload, client: client).page!
    expect(run.reload.completed?).to be(true)
    expect(Scrobble.count).to eq(2)
    expect(ImportPage.count).to eq(2)
    expect(ImportPage.first.raw_body).to include(" Artist ")
    expect(Scrobble.first.payload["artist_name"]).to eq(" Artist ")
    expect(Recording.count).to eq(0)
  end

  it "replays idempotently and retains different observations at the same second" do
    raw = page(1, track("One", 1000) + track("Two", 1000) + track("One", 1000) + '<track nowplaying="true"><name>Now</name></track>', pages: 1, total: 3)
    allow(client).to receive(:recent_tracks).and_return(raw)
    described_class.new(run, client: client).page!
    replay = user.import_runs.create!(source_username: "foo", upper_bound: 2000)
    expect { described_class.new(replay, client: client).page! }.not_to change(Scrobble, :count)
    expect(Scrobble.count).to eq(2)
    expect(Scrobble.where(recording_id: nil).count).to eq(2)
    expect(ImportPage.count).to eq(2)
  end

  it "rolls back inserted rows and raw page if the checkpoint cannot commit" do
    allow(client).to receive(:recent_tracks).and_return(page(1, track("One", 1000)))
    allow(run).to receive(:update!).and_raise(ActiveRecord::StatementInvalid)
    expect { described_class.new(run, client: client).page! }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Scrobble.count).to eq(0)
    expect(ImportPage.count).to eq(0)
    expect(run.reload.next_page).to eq(1)
  end

  it "fails safely on API errors and upstream page drift" do
    allow(client).to receive(:recent_tracks).and_return('<lfm status="failed"><error code="6">No user</error></lfm>')
    expect { described_class.new(run, client: client).page! }.to raise_error(Clients::InvalidResponse)
    expect(run.reload.next_page).to eq(1)
    expect(Scrobble.count).to eq(0)
  end
end
