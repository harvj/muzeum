class ResolutionWorkspaceController < ApplicationController
  before_action :workspace
  before_action :observation, except: :index

  def index
    @filter = params[:filter].presence_in(RecordingResolution::Workspace::FILTERS)
    result = @workspace.list(filter: @filter, before_id: params[:before].to_i)
    @rows = result.first(RecordingResolution::Workspace::PAGE)
    @next_page = @rows.last.first if result.size > @rows.size
  end

  def show
    @surface = @workspace.surface(@observation)
    matching = @workspace.matching(@observation)
    @observations_count = matching.count
    @scrobbles = RecordingResolution::Ledger.effective(current_user).where(id: matching.select(:id)).order(id: :desc)
    @scrobbles = @scrobbles.where("scrobbles.id < ?", params[:before].to_i) if params[:before].to_i.positive?
    @scrobbles = @scrobbles.limit(31).to_a
    @next_scrobble = @scrobbles.pop && @scrobbles.last.id if @scrobbles.size > 30
    @history = @workspace.history(@surface)
    @surface_head = @history.find_by(user_id: current_user.id, scrobble_id: nil)
    @inherited_head = @surface_head unless @surface_head&.mode == "inherit"
    @inherited_head ||= @history.find_by(user_id: nil, scrobble_id: nil)
    @exception_heads = @history.where(user_id: current_user.id, scrobble_id: @scrobbles.map(&:id)).group_by(&:scrobble_id).transform_values(&:first)
    @selected_scrobble = matching.find(params[:play]) if params[:play].present?
    @assessments = @workspace.assessments(@surface)
    @assessment = if params[:assessment].present?
      @assessments.find(params[:assessment])
    else
      claims = (@selected_scrobble || @observation).payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
      matching_claims = RecordingResolution::Group.where(claims:).select(:id)
      @assessments.where(group_id: matching_claims).where("evidence->>'partial' IS DISTINCT FROM 'true'").first ||
        @assessments.where(group_id: matching_claims).first
    end
    older = params[:assessment_before].to_i
    assessment_history = older.positive? ? @assessments.where("id < ?", older) : @assessments
    @assessment_history = assessment_history.limit(21).to_a
    @next_assessment = @assessment_history.pop && @assessment_history.last.id if @assessment_history.size > 20
    @assessment_request = CatalogImport.latest("assessment", @surface.id) if @surface
    @candidates = RecordingResolution::Workspace.candidates(@assessment)
    if @selected_scrobble
      @selected_head = @history.find_by(user_id: current_user.id, scrobble_id: @selected_scrobble.id)
      @selected_effective = RecordingResolution::Ledger.effective(current_user).find(@selected_scrobble.id)
    end
    @current_recording_id = @selected_effective ? @selected_effective.effective_recording_id : @inherited_head&.recording_id
    @current_recording = Recording.find_by(id: @current_recording_id) if @current_recording_id
    @recording_titles = Recording.where(id: @scrobbles.map(&:effective_recording_id).compact).pluck(:id, :title).to_h
    @history = @history.where("id < ?", params[:history_before].to_i) if params[:history_before].to_i.positive?
    @history = @history.limit(21).to_a
    @next_history = @history.pop && @history.last.id if @history.size > 20
  end

  def investigate
    request = nil
    ActiveRecord::Base.transaction do
      current_user.user_lastfm_accounts.active.lock.find_by!(lastfm_account_id: @observation.lastfm_account_id)
      surface = RecordingResolution::Ledger.attach!(@observation)
      request = CatalogImport.request!("assessment", surface.id, "observation_id" => @observation.id, "requester_id" => current_user.id)
    end
    request.dispatch
    redirect_to resolution_surface_path(@observation), status: :see_other
  end

  def decide
    scope = { "surface" => :surface, "scrobble" => :scrobble }.fetch(params[:scope]) { raise ArgumentError }
    mode = params[:mode].presence_in(%w[resolved unresolved inherit]) || raise(ArgumentError)
    reason = params[:reason].to_s.strip.presence || raise(ArgumentError)
    raise ArgumentError if reason.length > 500

    target = scope == :scrobble ? @workspace.matching(@observation).find(params[:play_id]) : @observation
    surface = @workspace.surface(@observation)
    assessment = @workspace.assessments(surface).find(params[:assessment_id]) if params[:assessment_id].present?
    request = context = nil
    ActiveRecord::Base.transaction do
      recording, context = selection(assessment, target) if mode == "resolved"
      RecordingResolution::Ledger.record!(listener: current_user, scrobble: target, scope:, mode:, reason:, recording:,
        assessment:, expected_head: params[:head].presence&.then { |value| Integer(value) })
      request = CatalogImport.request!("recording", recording.id, context) if recording
    end
    request&.dispatch
    notice = "Recording decision saved."
    if request && request.context["edition_mbid"] != context["edition_mbid"]
      notice += " Another import is in progress. Request the selected release again after it finishes."
    end
    redirect_to resolution_surface_path(@observation, play: scope == :scrobble ? target.id : nil),
      notice:, status: :see_other
  rescue ActiveRecord::StaleObjectError
    redirect_to resolution_surface_path(@observation), alert: "This assignment changed. Review the current decision and submit again.", status: :see_other
  rescue ArgumentError, CanonicalCatalog::Store::Unverified
    redirect_to resolution_surface_path(@observation), alert: "Choose a candidate and scope, and provide a reason of up to 500 characters.", status: :see_other
  end

  def admit
    target = params[:play_id].present? ? @workspace.matching(@observation).find(params[:play_id]) : @observation
    request = nil
    ActiveRecord::Base.transaction do
      current_user.user_lastfm_accounts.active.lock.find_by!(lastfm_account_id: target.lastfm_account_id)
      surface = @workspace.surface(target)
      surface&.lock!
      assessment = @workspace.assessments(surface).find(params[:assessment_id])
      recording, context = selection(assessment, target)
      raise ArgumentError if context["edition_mbid"].blank?

      if params[:play_id].present?
        current = RecordingResolution::Ledger.effective(current_user).find(target.id).effective_recording_id
      else
        history = @workspace.history(surface).where(scrobble_id: nil)
        head = history.find_by(user_id: current_user.id)
        head = history.find_by(user_id: nil) if head.nil? || head.mode == "inherit"
        current = head&.recording_id
      end
      raise ArgumentError unless current == recording.id

      request = CatalogImport.request!("recording", recording.id, context)
    end
    request.dispatch
    notice = if request.context["edition_mbid"] == params[:edition_mbid]
      "Release verification requested."
    else
      "Another import is in progress. Request this release again after it finishes."
    end
    redirect_to resolution_surface_path(@observation, play: params[:play_id].presence), notice:, status: :see_other
  rescue ArgumentError, CanonicalCatalog::Store::Unverified
    redirect_to resolution_surface_path(@observation), alert: "Choose a release for the current recording assignment.", status: :see_other
  end

  private

  def workspace
    @workspace = RecordingResolution::Workspace.new(current_user)
  end

  def observation
    @observation = @workspace.observations.find(params[:id])
  end

  def selection(assessment, target)
    candidate = RecordingResolution::Workspace.candidates(assessment).find { |item| item["id"] == params[:recording_mbid] }
    raise ArgumentError unless candidate

    edition = params[:edition_mbid].presence
    if edition && RecordingResolution::Workspace.editions(candidate, assessment).none? { |_, id| id == edition }
      raise ArgumentError
    end
    observed_edition = assessment.evidence.dig("edition", "id")
    context = { "album" => target.payload["album_name"], "observed_edition_mbid" => observed_edition,
      "edition_mbid" => edition, "assessment_id" => assessment.id }.compact
    [ CanonicalCatalog::Store.recording!(candidate), context ]
  end
end
