# A deliberately narrow review rule for one missing position between two observed plays.
class ShortTrackInference
  VERSION = "exact-track-gap-v1"
  MAX_REVIEW_PLAYS = 30
  Proposal = Data.define(:before_play, :after_play, :recording_id, :title, :evidence)

  def initialize(user, release, configuration)
    @user = user
    @release = release
    @configuration = configuration
  end

  def proposals(plays)
    return [] unless @release.catalog_verified_at

    plays.first(MAX_REVIEW_PLAYS).reverse.each_cons(2).filter_map { |before, after| check(before, after) }
  end

  def history
    grants = @user.user_lastfm_accounts.active.select(:lastfm_account_id)
    ShortTrackInferenceDecision.where(user: @user, release: @release,
      before_play_id: Scrobble.where(lastfm_account_id: grants).select(:id))
  end

  def record!(before_id:, after_id:, recording_id:, evidence_digest:, decision:)
    raise ArgumentError unless decision.in?(%w[confirmed rejected]) && @release.catalog_verified_at

    @user.with_lock do
      @configuration = ReleaseConfigurationSelection.new(@user, [ @release.id ]).configuration(@release)
      @sequences = nil
      raise ArgumentError unless [ before_id, after_id ].all? { |id| id.is_a?(String) && id.match?(/\A[1-9][0-9]*\z/) } && before_id != after_id

      anchors = RecordingResolution::Ledger.effective(@user).find([ before_id, after_id ])
      before, after = anchors.index_by { |play| play.id.to_s }.values_at(before_id, after_id)
      proposal = check(before, after)
      unless proposal && proposal.recording_id.to_s == recording_id && digest(proposal) == evidence_digest
        raise ArgumentError, "The listening evidence changed. Review the current proposal."
      end

      stream = history.where(before_play: before, after_play: after, recording_id: proposal.recording_id)
      head = stream.order(id: :desc).first
      if head&.decision != decision || head.evidence != proposal.evidence
        stream.create!(user: @user, release: @release, decision:, predecessor: head, evidence: proposal.evidence)
      end
    end
  end

  def digest(proposal)
    Digest::SHA256.hexdigest(proposal.evidence.to_json)
  end

  private

  def check(before, after)
    return unless before.lastfm_account_id == after.lastfm_account_id && before.played_at < after.played_at

    matches = sequences.select do |left, missing, right|
      left["recording_id"] == before.effective_recording_id && right["recording_id"] == after.effective_recording_id &&
        missing["recording_id"] && [ left, missing, right ].pluck("recording_id").compact.uniq.size == 3
    end
    return unless matches.one?

    left, missing, right = matches.first
    return unless missing.fetch("title").match?(/\b(?:intro|interlude)\b/i)

    left_length, short_length, right_length = [ left, missing, right ].pluck("duration_ms")
    return unless [ left_length, short_length, right_length ].all? { |duration| duration.is_a?(Integer) && duration.positive? } &&
      short_length < [ left_length, right_length ].min

    seconds = after.played_at - before.played_at
    return unless seconds == ((left_length + short_length) / 1000.0).round
    return unless Scrobble.where(lastfm_account_id: before.lastfm_account_id, played_at: before.played_at..after.played_at)
      .order(:played_at, :id).limit(3).ids == [ before.id, after.id ]

    Proposal.new(before, after, missing.fetch("recording_id"), missing.fetch("title"), {
      "version" => VERSION, "source_edition_mbid" => @configuration&.edition_mbid || @release.ingested_from_release_mbid,
      "configuration_id" => @configuration&.id, "slots" => [ left, missing, right ],
      "before" => [ before.id, before.played_at.iso8601, before.effective_recording_decision_id ],
      "after" => [ after.id, after.played_at.iso8601, after.effective_recording_decision_id ],
      "elapsed_seconds" => seconds.to_i
    })
  end

  def sequences
    @sequences ||= slots.each_cons(3).select do |left, middle, right|
      left["medium"] == middle["medium"] && middle["medium"] == right["medium"] &&
        left["position"] + 1 == middle["position"] && middle["position"] + 1 == right["position"]
    end
  end

  def slots
    if @configuration
      recordings = ReleaseConfiguration.recordings_by_source(@configuration.tracks.pluck("source_recording_mbid"))
      @configuration.tracks.map do |track|
        track.slice("medium", "position", "title", "duration_ms", "source_recording_mbid", "track_mbid")
          .merge("recording_id" => recordings[track.fetch("source_recording_mbid")]&.id)
      end
    else
      @release.catalog_track_slots.base_sequence.order(:medium, :position).map do |slot|
        slot.attributes.slice("medium", "position", "title", "duration_ms", "source_recording_mbid", "track_mbid", "recording_id")
      end
    end
  end
end
