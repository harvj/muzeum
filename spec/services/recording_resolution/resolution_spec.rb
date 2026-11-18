require "rails_helper"

RSpec.describe RecordingResolution do
  include ActiveSupport::Testing::TimeHelpers

  let(:ids) { RecordingResolution::FixtureTransport::IDS }
  let(:listener) { User.create!(lastfm_username: "resolution_archive", oidc_issuer: OidcClient::ISSUER, oidc_subject: "first") }
  let(:other) { User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "second") }
  let(:archive) { listener.source_account }
  let(:ledger) { RecordingResolution::Ledger }
  let(:pilot_runner) { RecordingResolution::PilotRunner }

  def observation(title: "Signals", album: "Night Drive", claim: :studio, account: archive)
    Scrobble.create!(user: account.archive_user, lastfm_account: account, played_at: Time.current,
      source_fingerprint: SecureRandom.hex(32),
      payload: { artist_name: "Night Lines", track_name: title, album_name: album, track_mbid: ids[claim],
        artist_mbid: ids[:artist], album_mbid: album && ids[:edition] })
  end

  def recording(title)
    Recording.create!(mbid: SecureRandom.uuid, title:)
  end

  def decide(scrobble, scope, mode, selection = nil, head: nil, user: listener)
    ledger.record!(listener: user, scrobble:, scope:, mode:, recording: selection,
      reason: "Reviewed original observation", expected_head: head&.id)
  end

  def effective(scrobble, user: listener)
    ledger.effective(user).find(scrobble.id).effective_recording_id
  end

  def select_work(scrobble, live: false)
    pilot = pilot_runner.start!(archive_id: archive.id, upper_id: scrobble.id, live:)
    pilot_runner.select!(pilot)
    RecordingResolution::Work.where(pilot_id: pilot.id).order(:id).last
  end

  it "uses exact archive tuples, distinguishes nil and empty albums, and attaches idempotently" do
    first = observation(album: nil)
    same_text = observation(album: nil, claim: :other)
    empty = observation(album: "")
    changed_case = observation(title: "signals", album: nil)
    expect(ledger.attach!(first).id).to eq(ledger.attach!(same_text).id)
    expect { ledger.attach!(first) }.not_to change(RecordingResolution::Membership, :count)
    expect([ first, empty, changed_case ].map { |event| ledger.attach!(event).id }.uniq.size).to eq(3)
  end

  it "inherits defaults for historical and future plays while preserving individual assignments and history" do
    first = observation
    second = observation
    studio, live, alternate = %w[Studio Live Alternate].map { |title| recording(title) }
    default = decide(first, :surface, "resolved", studio)
    exception = decide(second, :scrobble, "resolved", live)
    expect(effective(first)).to eq(studio.id)
    expect(effective(second)).to eq(live.id)

    changed = decide(first, :surface, "resolved", alternate, head: default)
    fourth = observation
    expect(RecordingResolution::Membership.exists?(fourth.id)).to be false
    expect(effective(fourth)).to eq(alternate.id)
    expect(effective(second)).to eq(live.id)

    unresolved = decide(second, :scrobble, "unresolved", head: exception)
    expect(effective(second)).to be_nil
    inherited = decide(second, :scrobble, "inherit", head: unresolved)
    expect(effective(second)).to eq(alternate.id)
    expect(inherited.predecessor_id).to eq(unresolved.id)
    expect(changed.predecessor_id).to eq(default.id)
    expect do
      RecordingResolution::Decision.transaction(requires_new: true) { inherited.update!(reason: "changed") }
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect { decide(first, :surface, "unresolved", head: default) }.to raise_error(ActiveRecord::StaleObjectError)
  end

  it "shares provider evidence while keeping independent assignments and revoked access private" do
    event = observation
    LastfmAccount.associate!(other, archive.username)
    owner_choice, other_choice = %w[Owner Other].map { |title| recording(title) }
    decide(event, :surface, "resolved", owner_choice)
    expect(effective(event, user: other)).to be_nil
    work = select_work(event)
    RecordingResolution::Processor.new(work).call
    assessment = RecordingResolution::Assessment.find(work.reload.assessment_id)
    expect(ledger.assessments(other)).to contain_exactly(assessment)
    expect(ledger.history(other)).to be_empty
    expect(assessment.evidence).not_to have_key("user_id")
    expect(assessment.evidence.to_json).not_to include("Reviewed original observation")
    decide(event, :surface, "resolved", other_choice, user: other)
    expect(effective(event, user: other)).to eq(other_choice.id)
    expect(effective(event)).to eq(owner_choice.id)

    query = ledger.effective(other)
    other.user_lastfm_accounts.active.find_by!(lastfm_account_id: archive.id).revoke!
    expect(query.where(id: event.id)).to be_empty
    expect(ledger.assessments(other)).to be_empty
    expect(ledger.history(other)).to be_empty
    expect do
      decide(event, :scrobble, "unresolved", user: other)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "applies all precedence layers, including an explicit unresolved surface masking an automatic default" do
    event = observation
    work = select_work(event)
    RecordingResolution::Processor.new(work).call
    assessment = RecordingResolution::Assessment.find(work.reload.assessment_id)
    # Simulate a previously accepted automatic decision. The worker cannot write it.
    auto = RecordingResolution::Decision.create!(surface_id: ledger.attach!(event).id, assessment_id: assessment.id,
      recording_id: assessment.suggested_recording_id, mode: "resolved", version: "test",
      actor: "reviewed-automatic-policy", reason: "test precedence", evidence: {})
    expect(effective(event)).to eq(auto.recording_id)
    blocker = decide(event, :surface, "unresolved")
    expect(effective(event)).to be_nil
    decide(event, :surface, "inherit", head: blocker)
    expect(effective(event)).to eq(auto.recording_id)
  end

  corpus = JSON.parse(Rails.root.join("spec/fixtures/recording_resolution/corpus.json").read)
  corpus.each do |example|
    it "evaluates #{example.fetch('case')} in the labeled two-provider corpus" do
      event = observation(title: example["track"], album: example["album"], claim: example["claim"]&.to_sym)
      before = event.attributes
      work = select_work(event)
      transport = RecordingResolution::FixtureTransport.new(example)
      processor = RecordingResolution::Processor.new(work, fixture: transport)
      expect { processor.call }.not_to change(RecordingResolution::Decision, :count)
      assessment = RecordingResolution::Assessment.find(work.reload.assessment_id)
      expect(assessment.evidence.fetch("reason_details").keys).to match_array(assessment.evidence.fetch("reasons"))
      if example["alternative"]
        expect(assessment.evidence.dig("reason_details", "competing_recordings", "candidate_mbids")).to eq([ ids[:other] ])
      end
      accepted = example["expected"] == "accept"
      expect(assessment.suggested_recording_id.present?).to eq(accepted)
      expect(assessment.evidence.dig("discogs", "status")).to eq("contradicts") if example["discogs_track"]
      expect(assessment.evidence.dig("verification", "redirected_from")).to eq(ids[:redirect]) if example["claim"] == "redirect"
      expect { processor.call }.not_to change(RecordingResolution::Assessment, :count)
      replay = select_work(event)
      expect do
        RecordingResolution::Processor.new(replay, fixture: transport).call
      end.not_to change(RecordingResolution::Assessment, :count)
      expect(event.reload.attributes).to eq(before)
      expect(effective(event)).to be_nil
    end
  end

  it "persists Retry-After and recovers without duplicate work or decisions" do
    freeze_time do
      work = select_work(observation)
      good = RecordingResolution::FixtureTransport.new
      transport = lambda do |provider, path, params|
        if provider == :discogs && work.attempts.zero?
          [ 429, { "Retry-After" => "20" }, "" ]
        else
          good.call(provider, path, params)
        end
      end
      processor = RecordingResolution::Processor.new(work, fixture: transport)
      processor.call
      expect(work.reload).to have_attributes(state: "pending", due_at: 20.seconds.from_now, attempts: 1)
      expect { processor.call }.not_to change { work.reload.attempts }
      travel 20.seconds
      processor.call
      expect(work.reload.state).to eq("done")
      expect(RecordingResolution::Pilot.find(work.pilot_id).musicbrainz_requests).to eq(3)
    end
  end

  it "allows only the lease owner to fetch and finalize while a competing job runs" do
    work = select_work(observation)
    fixture = RecordingResolution::FixtureTransport.new
    contender = instance_double(RecordingResolution::FixtureTransport)
    expect(contender).not_to receive(:call)
    during_fetch = lambda do |provider, path, params|
      competing_work = RecordingResolution::Work.find(work.id)
      RecordingResolution::Processor.new(competing_work, fixture: contender).call
      fixture.call(provider, path, params)
    end

    expect do
      RecordingResolution::Processor.new(work, fixture: during_fetch).call
    end.to change(RecordingResolution::Assessment, :count).by(1)
    expect(work.reload.state).to eq("done")
  end

  it "backs off a MusicBrainz outage while allowing independent archive capture" do
    work = select_work(observation)
    outage = ->(*) { [ 503, { "Retry-After" => "30" }, "" ] }
    before = Time.current
    RecordingResolution::Processor.new(work, fixture: outage).call
    expect(work.reload.state).to eq("pending")
    expect(work.attempts).to eq(1)
    expect(work.due_at).to be >= before + 30.seconds
    expect { observation }.to change(Scrobble, :count).by(1)
    evidence = ledger.assessments(listener).sole.evidence
    expect(evidence.dig("reason_details", "provider_temporarily_unavailable")).to include(
      "provider" => "musicbrainz", "endpoint" => "/ws/2/recording", "retry_exhausted" => false)
  end

  it "resumes a failed Discogs page from cached evidence and deduplicates the failure assessment" do
    freeze_time do
      work = select_work(observation)
      fixture = RecordingResolution::FixtureTransport.new
      page_one = { pagination: { page: 1, pages: 2, items: 2, per_page: 1 }, results: [ { id: 42, title: "Unrelated" } ] }
      page_two = { pagination: { page: 2, pages: 2, items: 2, per_page: 1 },
        results: [ { id: 123, title: "Night Lines - Night Drive" } ] }
      transport = lambda do |provider, path, params|
        next fixture.call(provider, path, params) unless provider == :discogs && path == "/database/search"
        next [ 200, {}, page_one.to_json ] if params[:page] == 1
        next [ 503, { "Retry-After" => "20" }, "" ] if work.attempts < 2

        [ 200, {}, page_two.to_json ]
      end
      processor = RecordingResolution::Processor.new(work, fixture: transport)
      processor.call
      failure = ledger.assessments(listener).sole.evidence
      expect(failure.dig("discogs", "search_pages").pluck("page")).to eq([ 1 ])
      expect(failure.dig("reason_details", "provider_temporarily_unavailable", "parameters", "page")).to eq(2)
      expect(failure.dig("verified_recording", "id")).to eq(ids[:studio])
      travel 20.seconds
      expect { processor.call }.not_to change(RecordingResolution::Assessment, :count)
      travel 20.seconds
      expect { processor.call }.to change(RecordingResolution::Assessment, :count).by(1)
      expect(work.reload.state).to eq("done")
      expect(RecordingResolution::Pilot.find(work.pilot_id)).to have_attributes(musicbrainz_requests: 3, discogs_requests: 5)
    end
  end

  it "records exhaustion after five transient failures and stops requesting" do
    freeze_time do
      work = select_work(observation)
      processor = RecordingResolution::Processor.new(work, fixture: ->(*) { [ 503, { "Retry-After" => "30" }, "" ] })
      5.times do
        processor.call
        travel 30.seconds
      end

      expect(work.reload).to have_attributes(state: "failed", attempts: 5)
      expect { processor.call }.not_to change { work.reload.attempts }
      failures = ledger.assessments(listener).map { |assessment|
        assessment.evidence.dig("reason_details", "provider_temporarily_unavailable", "retry_exhausted")
      }
      expect(failures).to contain_exactly(false, true)
      expect(RecordingResolution::Pilot.find(work.pilot_id).musicbrainz_requests).to eq(5)
    end
  end

  it "stops at the pilot provider budget and records the failed endpoint without another request" do
    work = select_work(observation)
    pilot = RecordingResolution::Pilot.find(work.pilot_id)
    pilot.update!(discogs_requests: RecordingResolution::ProviderSession::LIMITS.fetch(:discogs))
    transport = RecordingResolution::FixtureTransport.new
    allow(transport).to receive(:call).and_call_original
    RecordingResolution::Processor.new(work, fixture: transport).call

    expect(work.reload).to have_attributes(state: "failed", attempts: 1)
    expect(transport).not_to have_received(:call).with(:discogs, anything, anything)
    expect(ledger.assessments(listener).sole.evidence.dig("reason_details", "provider_request_stopped")).to include(
      "provider" => "discogs", "endpoint" => "/database/search", "message" => "discogs pilot request limit reached")
  end

  it "rejects stale leases after an interrupted worker is reclaimed" do
    work = select_work(observation)
    stale = SecureRandom.uuid
    work.update!(state: "leased", lease_token: stale, lease_until: 1.second.ago)
    RecordingResolution::Processor.new(work).call
    expect(work.reload.state).to eq("done")
    expect do
      RecordingResolution::ProviderSession.assert_lease!(work, stale)
    end.to raise_error(ActiveRecord::StaleObjectError)
  end

  it "does not select observations past the immutable upper bound" do
    first = observation
    later = observation(title: "Later")
    work = select_work(first)
    pilot_runner.select!(RecordingResolution::Pilot.find(work.pilot_id))
    expect(RecordingResolution::Work.where(pilot_id: work.pilot_id).count).to eq(1)
    expect(RecordingResolution::Membership.exists?(later.id)).to be false
  end
end
