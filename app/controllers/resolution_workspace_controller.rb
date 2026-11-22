class ResolutionWorkspaceController < ApplicationController
  before_action :workspace
  before_action :observation, except: :index
  before_action :authorize_management, only: %i[investigate decide defer release_batch confirm_release_batch]

  def index
    @filter = params[:filter].presence_in(RecordingResolution::Workspace::FILTERS)
    result = @workspace.list(filter: @filter, before_id: params[:before].to_i, before_count: params[:before_count].to_i)
    @rows = result.first(RecordingResolution::Workspace::PAGE)
    if result.size > @rows.size
      @next_page = @rows.last.first
      @next_count = @rows.last[4] if @filter == "unresolved"
    end
  end

  def show
    @observation = @workspace.matching(@observation).find(params[:play]) if params[:play].present?
    @may_manage_observation = current_user.managed_archive_grants.exists?(lastfm_account_id: @observation.lastfm_account_id)
    @surface = @workspace.surface(@observation)
    ids, @observations_count = @workspace.matching_page(@observation, before_id: params[:before].to_i)
    @next_scrobble = ids.pop && ids.last if ids.size > RecordingResolution::Workspace::PAGE
    @scrobbles = RecordingResolution::Ledger.effective(current_user).where(id: ids).order(id: :desc).to_a
    @history = @workspace.history(@surface)
    @surface_head = @history.find_by(user_id: current_user.id, scrobble_id: nil)
    @inherited_head = @surface_head unless @surface_head&.mode == "inherit"
    @inherited_head ||= @history.find_by(user_id: nil, scrobble_id: nil)
    @exception_heads = @history.where(user_id: current_user.id, scrobble_id: @scrobbles.map(&:id)).group_by(&:scrobble_id).transform_values(&:first)
    @selected_scrobble = @observation
    @assessments = @workspace.assessments(@surface)
    @assessment = if params[:assessment].present?
      @assessments.find(params[:assessment])
    else
      claims = (@selected_scrobble || @observation).payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
      matching_claims = RecordingResolution::Group.where(claims:).select(:id)
      @assessments.where(group_id: matching_claims)
        .reorder(Arel.sql("(evidence->>'partial' IS NOT DISTINCT FROM 'true') ASC"), id: :desc).first
    end
    older = params[:assessment_before].to_i
    assessment_history = older.positive? ? @assessments.where("id < ?", older) : @assessments
    @assessment_history = assessment_history.select(:id, :created_at).limit(21).to_a
    @next_assessment = @assessment_history.pop && @assessment_history.last.id if @assessment_history.size > 20
    target = @selected_scrobble || @observation
    investigation = RecordingResolution::Investigation.new(current_user, target)
    group = investigation.group(@surface)
    @assessment_request = CatalogImport.latest(RecordingResolution::Investigation::KIND, group.id) if group
    legacy_request = CatalogImport.latest("assessment", @surface.id) if @assessment_request.nil? && @surface
    @assessment_request ||= legacy_request if legacy_request&.active?
    @ranking = if @assessment
      if params[:assessment].present? && @assessment.evidence["ranking"]
        @assessment.evidence["ranking"]
      else
        RecordingResolution::Ranking.call(@surface, @assessment.evidence, source_hints: true)
      end
    else
      []
    end
    @review_releases = RecordingResolution::ReviewRelease.for_assessment(@assessment)
    @assessment_matches_claims = params[:assessment].blank? || assessment_matches_claims?(@assessment, target)
    if @may_manage_observation && @assessment && @assessment_matches_claims
      review = RecordingResolution::ListenerReleaseReview.new(current_user, target, @assessment)
      if (ranking = review.ranked(@surface))
        @ranking = ranking
        @listener_ranking_token = review.token(@ranking)
      end
    end
    display_evidence = @assessment&.evidence || {}
    display_evidence = display_evidence.except("verified_recording") if @ranking.first&.fetch("version") == RecordingResolution::Ranking::SOURCE_HINTS_VERSION
    legacy_candidates = RecordingResolution::Workspace.candidate_evidence(display_evidence).index_by { |candidate| candidate["id"] }
    @candidates = @ranking.filter_map { |rank| legacy_candidates[rank["recording_mbid"]] }
    @catalog_context = RecordingResolution::CatalogContext.new(@candidates, @review_releases)
    current = @scrobbles.find { |play| play.id == target.id } || RecordingResolution::Ledger.effective(current_user).find(target.id)
    @current_decision = @inherited_head
    if (@assessment.nil? || @assessment.evidence["partial"]) && @assessment_request.nil? && @inherited_head&.recording_id.nil? && @may_manage_observation &&
        params[:assessment].blank? && params[:before].blank? && params[:history_before].blank?
      @assessment_request = investigation.request
    end
    @assessment_request ||= legacy_request
    if @selected_scrobble
      @selected_head = @history.find_by(user_id: current_user.id, scrobble_id: @selected_scrobble.id)
    end
    @current_recording_id = @inherited_head&.recording_id
    overrides = protected_plays(@surface).where(scrobble_id: @workspace.matching(target).select(:id)).reorder(nil).group(:mode).count
    @override_count = overrides.values.sum
    @affected_count = @observations_count - @override_count
    @inheriting_count = @current_recording_id ? @affected_count : 0
    @unresolved_count = @affected_count - @inheriting_count + overrides.fetch("unresolved", 0)
    @current_recording = Recording.find_by(id: @current_recording_id) if @current_recording_id
    effective_decision = @history.find_by(id: current.effective_recording_decision_id) if current.effective_recording_decision_id
    if @may_manage_observation && current.effective_recording_id && effective_decision&.user_id == current_user.id &&
        !effective_decision.evidence.key?("release_batch")
      @batch_releases = Release.joins(:catalog_track_slots).where(catalog_track_slots: { recording_id: current.effective_recording_id })
        .where.not(catalog_verified_at: nil).distinct.order(:id).limit(5)
    end
    @history = @history.where("id < ?", params[:history_before].to_i) if params[:history_before].to_i.positive?
    @history = @history.limit(21).to_a
    recording_ids = @scrobbles.map(&:effective_recording_id) + @history.map(&:recording_id) + [ @inherited_head&.recording_id ]
    @recordings = Recording.where(id: recording_ids.compact.uniq).index_by(&:id)
    @next_history = @history.pop && @history.last.id if @history.size > 20
  end

  def investigate
    manual = params[:manual_mbid].to_s.strip.presence
    if manual && !Clients::Musicbrainz::MBID.match?(manual)
      return redirect_to resolution_surface_path(@observation), alert: "Enter a MusicBrainz recording identifier.", status: :see_other
    end
    release_mbid = params[:release_mbid].presence
    if release_mbid
      assessment = @workspace.assessments(@workspace.surface(@observation)).find(params[:assessment_id])
      references = RecordingResolution::Workspace.candidates(assessment).flat_map do |candidate|
        Array(candidate["releases"]).pluck("id") + [ candidate.dig("release_discovery", "id"), candidate.dig("local_release_context", "edition_mbid") ]
      end
      references << assessment.evidence.dig("edition", "id")
      unless assessment_matches_claims?(assessment, @observation) &&
          Clients::Musicbrainz::MBID.match?(release_mbid.to_s) && references.include?(release_mbid)
        return redirect_to resolution_surface_path(@observation), alert: "Select a supporting release from this assessment.", status: :see_other
      end
    end
    RecordingResolution::Investigation.new(current_user, @observation).request(refresh: true, manual_mbid: manual, release_mbid:)
    redirect_to resolution_surface_path(@observation, play: params[:play].presence), status: :see_other
  end

  def decide
    scope = { "surface" => :surface, "scrobble" => :scrobble }.fetch(params[:scope]) { raise ArgumentError }
    mode = params[:mode].presence_in(%w[resolved unresolved inherit]) || raise(ArgumentError)
    options = RecordingResolution::DecisionReasons::OPTIONS.fetch(mode)
    code = params[:reason_code].to_s.presence
    comment = params[:comment].to_s.strip.presence
    legacy_reason = params[:reason].to_s.strip.presence
    code ||= RecordingResolution::DecisionReasons::DEFAULTS.fetch(mode) unless legacy_reason
    reason = code ? options.fetch(code) { raise ArgumentError } : legacy_reason
    raise ArgumentError if reason.length > 500 || comment.to_s.length > 500

    target = scope == :scrobble ? @workspace.matching(@observation).find(params[:play_id]) : @observation
    surface = @workspace.surface(@observation)
    assessment = @workspace.assessments(surface).find(params[:assessment_id]) if params[:assessment_id].present?
    raise ArgumentError if assessment && !assessment_matches_claims?(assessment, target)
    request = nil
    ActiveRecord::Base.transaction do
      current_user.lock!
      current_user.managed_archive_grants.lock.find_by!(lastfm_account_id: target.lastfm_account_id)
      recording, context = selection(assessment, target) if mode == "resolved"
      previous = RecordingResolution::Ledger.effective(current_user).find(target.id)
      ranking = decision_ranking(assessment, surface, target)
      selected_rank = ranking&.find { |entry| entry["recording_mbid"] == recording&.mbid }
      if code == "verified_identifier" && selected_rank&.dig("inputs", "recording_identifier", "state") != "positive"
        raise ArgumentError
      end
      if code == "corroborating_evidence" && selected_rank&.dig("inputs", "edition_slot", "state") != "positive"
        raise ArgumentError
      end
      metadata = { "reason_code" => code, "comment" => comment, "scoring_version" => ranking&.first&.fetch("version"),
        "candidate_scores" => ranking&.map { |row| row.slice("recording_mbid", "score") },
        "previous_effective_recording_id" => previous.effective_recording_id, "previous_effective_decision_id" => previous.effective_recording_decision_id,
        "affected_scope" => scope.to_s,
        "review_snapshot" => RecordingResolution::ReviewSnapshot.capture(assessment:, ranking: ranking || [],
          feedback: { "resolved" => "selected", "unresolved" => "unresolved", "inherit" => "inherit" }.fetch(mode),
          candidate_mbid: recording&.mbid, affected_count: affected_count(target, surface, scope)) }.compact
      RecordingResolution::Ledger.record!(listener: current_user, scrobble: target, scope:, mode:, reason:, recording:,
        assessment:, metadata:, expected_head: params[:head].presence&.then { |value| Integer(value) })
      request = CatalogImport.request!("recording", recording.id, context) if recording
    end
    request&.dispatch
    notice = "Recording decision saved."
    redirect_to resolution_surface_path(target), notice:, status: :see_other
  rescue ActiveRecord::StaleObjectError
    redirect_to resolution_surface_path(@observation), alert: "This assignment changed. Review the current decision and submit again.", status: :see_other
  rescue ArgumentError, CanonicalCatalog::Store::Unverified
    redirect_to resolution_surface_path(@observation), alert: "Check the candidate and scope. Optional comments are limited to 500 characters.", status: :see_other
  end

  def defer
    comment = params[:comment].to_s.strip.presence
    raise ArgumentError if comment.to_s.length > 500

    feedback = (params[:feedback].presence || "deferred").presence_in(%w[deferred rejected]) || raise(ArgumentError)
    candidate_mbid = params[:recording_mbid].presence
    raise ArgumentError if feedback == "rejected" && candidate_mbid.nil?

    target = params[:play_id].present? ? @workspace.matching(@observation).find(params[:play_id]) : @observation
    scope = params[:play_id].present? ? :scrobble : :surface
    ActiveRecord::Base.transaction do
      current_user.lock!
      current_user.managed_archive_grants.lock.find_by!(lastfm_account_id: target.lastfm_account_id)
      surface = RecordingResolution::Ledger.attach!(target)
      head = @workspace.history(surface).where(user_id: current_user.id, scrobble_id: scope == :scrobble ? target.id : nil).first
      expected = params[:head].presence&.then { |value| Integer(value) }
      raise ActiveRecord::StaleObjectError.new(head || surface, "defer") unless head&.id == expected

      assessment = @workspace.assessments(surface).find(params[:assessment_id]) if params[:assessment_id].present?
      ranking = decision_ranking(assessment, surface, target)
      raise ArgumentError if assessment && !assessment_matches_claims?(assessment, target)
      raise ArgumentError if candidate_mbid && !Array(ranking).any? { |row| row["recording_mbid"] == candidate_mbid }
      code = feedback == "rejected" ? "rejected_candidate" : "deferred_review"
      snapshot = RecordingResolution::ReviewSnapshot.capture(assessment:, ranking: ranking || [], feedback:,
        candidate_mbid:, affected_count: 0)

      RecordingResolution::Ledger.record!(listener: current_user, scrobble: target, scope:,
        mode: head&.mode || "inherit", reason: feedback == "rejected" ? "Rejected candidate" : "Deferred review", recording: Recording.find_by(id: head&.recording_id),
        assessment: RecordingResolution::Assessment.find_by(id: head&.assessment_id), expected_head: expected,
        metadata: { "reason_code" => code, "comment" => comment, "previous_decision_id" => head&.id,
          "affected_scope" => scope.to_s, "review_snapshot" => snapshot }.compact)
    end
    redirect_to resolution_surface_path(@observation, play: params[:play_id].presence), notice: feedback == "rejected" ? "Candidate rejected." : "Review deferred.", status: :see_other
  rescue ArgumentError, ActiveRecord::StaleObjectError
    redirect_to resolution_surface_path(@observation), alert: "This assignment changed. Review the current decision and submit again.", status: :see_other
  end

  def release_batch
    @batch = build_release_batch
    @proposals = @batch.proposals
    @batch_token = @batch.token(@proposals) if @proposals.any?
  rescue ArgumentError
    redirect_to resolution_surface_path(@observation), alert: "A verified complete release tracklist is required.", status: :see_other
  end

  def confirm_release_batch
    batch = build_release_batch
    choices = params[:choices]
    raise ArgumentError unless choices.is_a?(ActionController::Parameters)

    choices = choices.to_unsafe_h
    saved = batch.confirm!(params[:batch_token], choices, comment: params[:comment].to_s.strip.presence)
    redirect_to resolution_surface_path(batch.anchor), notice: "Review saved. Confirmed #{view_context.pluralize(saved, 'observation')}.", status: :see_other
  rescue ArgumentError, ActiveRecord::StaleObjectError
    redirect_to resolution_surface_path(@observation), alert: "Review changed or expired. Open a fresh batch.", status: :see_other
  end

  private

  def build_release_batch
    anchor = params[:play].present? ? @workspace.matching(@observation).find(params[:play]) : @observation
    RecordingResolution::ReleaseBatch.new(current_user, anchor, Release.find(params[:release_id]))
  end

  def decision_ranking(assessment, surface, target)
    return unless assessment

    if params[:listener_ranking_token].present?
      return RecordingResolution::ListenerReleaseReview.new(current_user, target, assessment).read(params[:listener_ranking_token])
    end

    RecordingResolution::Ranking.call(surface, assessment.evidence, source_hints: true)
  end

  def authorize_management
    head :forbidden unless current_user.managed_archive_grants.exists?(lastfm_account_id: @observation.lastfm_account_id)
  end

  def workspace
    @workspace = RecordingResolution::Workspace.new(current_user)
  end

  def observation
    @observation = @workspace.observations.find(params[:id])
  end

  def affected_count(target, surface, scope)
    return 1 if scope == :scrobble

    @workspace.matching(target).where.not(id: protected_plays(surface).select(:scrobble_id)).count
  end

  def protected_plays(surface)
    @workspace.history(surface).where(user_id: current_user.id).where.not(scrobble_id: nil)
      .where.not(mode: "inherit").where("NOT EXISTS (SELECT 1 FROM resolution_decisions successor WHERE successor.predecessor_id = resolution_decisions.id)")
      .reorder(nil)
  end

  def assessment_matches_claims?(assessment, target)
    RecordingResolution::Group.find(assessment.group_id).claims ==
      target.payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
  end

  def selection(assessment, target)
    candidate = RecordingResolution::Workspace.candidate_evidence(assessment.evidence.except("verified_recording"))
      .find { |item| item["id"] == params[:recording_mbid] }
    raise ArgumentError unless candidate
    if RecordingResolution::Ranking.call(@workspace.surface(target), assessment.evidence, source_hints: true)
        .none? { |entry| entry["recording_mbid"] == candidate["id"] }
      raise ArgumentError
    end

    context = { "assessment_id" => assessment.id }
    [ CanonicalCatalog::Store.recording!(candidate), context ]
  end
end
