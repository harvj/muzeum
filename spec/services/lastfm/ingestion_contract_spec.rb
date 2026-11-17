require "rails_helper"

RSpec.describe "P1.2 source contract", type: :model do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { User.create!(lastfm_username: "source", oidc_issuer: OidcClient::ISSUER, oidc_subject: "source-contract") }
  let(:account) { user.source_account }
  let(:run) { account.import_runs.create!(user: user, source_username: account.username, upper_bound: 2000, actor_kind: "user") }
  let(:client) { double("synthetic Last.fm") }

  def track(name = "Track", time = 1000, metadata = "")
    "<track>#{metadata}<artist>Artist</artist><name>#{name}</name><album>Album</album><date uts='#{time}'>UTC</date></track>"
  end

  def response(tracks, page: 1, pages: 1, total: 1)
    "<lfm status='ok'><recenttracks user='source' page='#{page}' totalPages='#{pages}' total='#{total}'>#{tracks}</recenttracks></lfm>"
  end

  def process(raw, target = run)
    allow(client).to receive(:recent_tracks).and_return(raw)
    Lastfm::HistoricalImporter.new(target, client: client).page!
  end

  def finish(raw, target = run)
    10.times do
      process(raw, target)
      break if target.reload.completed?
    end
    expect(target.reload).to be_completed
  end

  it "retains 201 distinguishable same-second tuples across pages and boundary sweeps" do
    first = (1..200).map { |i| track("Track #{i}") }.join
    last = track("Track 201")
    allow(client).to receive(:recent_tracks).and_return(response(first, pages: 2, total: 201),
      response(first, pages: 2, total: 201), response(last, page: 2, pages: 2, total: 201),
      response(last, page: 2, pages: 2, total: 201), response(first, pages: 2, total: 201), response(last, page: 2, pages: 2, total: 201))
    6.times { Lastfm::HistoricalImporter.new(run, client: client).page! }
    expect(run.reload).to be_completed
    expect(Scrobble.count).to eq(201)
    expect(SourceDelivery.count).to eq(603)
    expect(IngestionIssue.where(kind: "same_second")).to exist
  end

  it "records indistinguishable repeats and metadata changes without rewriting payloads or IDs" do
    raw = response(track + track, total: 2)
    finish(raw)
    original = Scrobble.sole.attributes
    replay = account.import_runs.create!(user: user, source_username: "source", upper_bound: 2000, kind: "replay")
    finish(response(track("Track", 1000, "<loved>1</loved><mbid>changed</mbid>")), replay)
    expect(Scrobble.sole.attributes).to eq(original)
    expect(IngestionIssue.where(kind: "repeat")).to exist
    expect(IngestionIssue.where(kind: "metadata_changed")).to exist
    expect(SourceDelivery.where(scrobble: Scrobble.sole).distinct.count(:source_checksum)).to eq(2)
  end

  it "retains malformed/undated/now-playing evidence but never creates listening events for them" do
    raw = response("<track nowplaying='true'><name>Now</name><date uts='1000'/></track><track><name>Undated</name></track>" +
      "<track><name>Invalid</name><date uts='garbage'/></track>" + track, total: 2)
    finish(raw)
    expect(Scrobble.count).to eq(1)
    expect(SourceDelivery.pluck(:classification)).to include("now_playing", "undated", "malformed")
    expect(run.excluded_count).to be >= 3
  end

  it "retains invalid UTF-8 response bytes and rejects them as source events" do
    raw = "<lfm>".b + [ 255 ].pack("C") + "</lfm>".b
    expect { process(raw) }.to raise_error(Clients::InvalidResponse)
    expect(SourceFetch.sole.raw_body.bytes).to eq(raw.bytes)
    expect(Scrobble.count).to eq(0)
    expect(run.reload.next_page).to eq(1)
  end

  it "retains the fetched response independently when the page/checkpoint transaction fails" do
    allow(SourceDelivery).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid)
    expect { process(response(track)) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Scrobble.count).to eq(0)
    expect(ImportPage.count).to eq(0)
    expect(SourceFetch.count).to eq(1)
    expect(run.reload.next_page).to eq(1)
  end

  it "safely resumes when the process loses acknowledgment after a committed page" do
    allow(Lastfm::PageWriter).to receive(:new).and_wrap_original do |method, *arguments, **keywords|
      writer = method.call(*arguments, **keywords)
      allow(writer).to receive(:commit!).and_wrap_original { |commit| commit.call; raise IOError, "lost acknowledgment" }
      writer
    end
    expect { process(response(track)) }.to raise_error(IOError)
    original_id = Scrobble.sole.id
    expect(run.reload.next_page).to eq(2)
    allow(Lastfm::PageWriter).to receive(:new).and_call_original
    finish(response(track))
    expect(Scrobble.sole.id).to eq(original_id)
  end

  it "does not advance a checkpoint on empty/malformed XML or changed source totals" do
    [ "", "<broken>", response("", total: 3) ].each do |raw|
      expect { process(raw) }.to raise_error(Clients::InvalidResponse)
      expect(run.reload.next_page).to eq(1)
    end
    process(response(track, pages: 2, total: 2))
    process(response(track)) # boundary
    expect { process(response(track("Later", 900), page: 2, pages: 2, total: 3)) }.to raise_error(Lastfm::SourceDrift)
    expect(run.reload.next_page).to eq(2)
    expect(SourceFetch.count).to eq(6)
    expect(IngestionIssue.where(kind: "source_drift")).to exist
  end

  it "rechecks import authorization after fetching and before committing" do
    allow(client).to receive(:recent_tracks) do
      user.user_lastfm_accounts.sole.revoke!
      response(track)
    end
    expect { Lastfm::HistoricalImporter.new(run, client: client).page! }.to raise_error(Lastfm::PermissionDenied)
    expect(Scrobble.count).to eq(0)
    expect(SourceFetch.count).to eq(1)
  end

  it "shares one source archive while keeping users and future interpretation permissions separate" do
    finish(response(track))
    other = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "other-viewer")
    shared = LastfmAccount.associate!(other, "SOURCE")
    expect(shared.id).to eq(account.id)
    expect(other.archive_observations.pluck(:id)).to eq(user.archive_observations.pluck(:id))
    other.user_lastfm_accounts.sole.revoke!
    expect(other.archive_observations.count).to eq(0)
    expect(user.archive_observations.count).to eq(1)
  end

  it "retains separate source identities for identical timestamps and names on different accounts" do
    finish(response(track))
    other = User.create!(lastfm_username: "other", oidc_issuer: OidcClient::ISSUER, oidc_subject: "other-source")
    target = other.import_runs.create!(source_username: "other", upper_bound: 2000)
    finish(response(track).sub("user='source'", "user='other'"), target)
    expect(Scrobble.count).to eq(2)
    expect(Scrobble.distinct.count(:source_fingerprint)).to eq(2)
  end

  it "preserves delayed/out-of-order completions within a bounded overlapping incremental interval" do
    finish(response(track))
    account.update!(synced_through: 1500)
    incremental = Lastfm::Scheduler.run_for!(account)
    expect(incremental.lower_bound).to eq(1)
    finish(response(track("Late", 900) + track("New", 1200) + track, total: 3), incremental)
    expect(Scrobble.order(:played_at).pluck(:played_at).map(&:to_i)).to eq([ 900, 1000, 1200 ])
    expect(Scrobble.count).to eq(3)
  end

  it "refuses a second writer while the source advisory lock is held" do
    id = account.id
    configuration = ActiveRecord::Base.connection_db_config.configuration_hash
    parameters = configuration.slice(:host, :port, :password)
    parameters[:user] = configuration[:username] if configuration[:username]
    parameters[:dbname] = configuration[:database]
    separate = PG.connect(**parameters)
    separate.exec("SELECT pg_advisory_lock(#{Lastfm::HistoricalImporter::LOCK_NAMESPACE}, #{id})")
    expect(client).not_to receive(:recent_tracks)
    expect(Lastfm::HistoricalImporter.new(run, client: client).page!).to be(false)
  ensure
    separate&.close
  end

  it "refuses account renames that would merge or reinterpret archives" do
    other = User.create!(lastfm_username: "reserved")
    expect { account.reconcile_name!("reserved", reason: "operator review") }.to raise_error(Lastfm::AccountConflict)
    account.reconcile_name!("renamed", reason: "provider rename verified by operator")
    expect(account.identity_key).to eq("source")
    expect(account.state).to eq("paused")
    expect { LastfmAccount.associate!(other, "source") }.to raise_error(Lastfm::AccountConflict)
  end

  it "enforces immutable evidence and account lineage through direct SQL/bulk operations" do
    finish(response(track))
    [ Scrobble.sole, SourceFetch.first, SourceDelivery.first, PageCommit.first, IngestionIssue.first, ImportPage.first ].compact.each do |record|
      expect { record.class.transaction(requires_new: true) { record.class.where(id: record.id).delete_all } }.to raise_error(ActiveRecord::StatementInvalid)
    end
    expect { Scrobble.transaction(requires_new: true) { Scrobble.sole.update_columns(lastfm_account_id: nil) } }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
