class ResolutionWorkspaceController < ApplicationController
  before_action :workspace
  before_action :observation, except: :index
  before_action :authorize_management, only: %i[investigate decide defer release_batch confirm_release_batch retain_configuration admit_adjacent_release select_reviewed_configuration]

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
    ids, @observations_count = @workspace.matching_page(@observation, before_id: params[:before])
    @next_scrobble = ids.pop && ids.last if ids.size > RecordingResolution::Workspace::PAGE
    @scrobbles = RecordingResolution::Ledger.effective(current_user).where(id: ids).order(played_at: :desc, id: :desc).to_a
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
    if params[:section] == "evidence" && @may_manage_observation && @assessment && @assessment_matches_claims
      @release_configurations = configurations_for(@assessment)
      @adjacent_programs = adjacent_programs_for(@assessment)
    end
    display_evidence = @assessment&.evidence || {}
    display_evidence = display_evidence.except("verified_recording") if @ranking.first&.fetch("version") == RecordingResolution::Ranking::SOURCE_HINTS_VERSION
    legacy_candidates = RecordingResolution::Workspace.candidate_evidence(display_evidence).index_by { |candidate| candidate["id"] }
    @candidates = @ranking.filter_map { |rank| legacy_candidates[rank["recording_mbid"]] }.uniq { |candidate| candidate.fetch("id") }
    @catalog_context = RecordingResolution::CatalogContext.new(@candidates)
    current = @scrobbles.find { |play| play.id == target.id } || RecordingResolution::Ledger.effective(current_user).find(target.id)
    @current_decision = @inherited_head
    if (@assessment.nil? || @assessment.evidence["partial"]) && @assessment_request.nil? && @inherited_head&.recording_id.nil? && @may_manage_observation &&
        params[:assessment].blank? && params[:before].blank? && params[:history_before].blank?
      @assessment_request = investigation.request
    end
    if @assessment && @assessment_matches_claims
      @release_review = RecordingResolution::ReleaseReview.new(@assessment.evidence)
      if @assessment.version.start_with?("workspace-evidence-") &&
          @assessment.version != RecordingResolution::Assessment::INTERPRETATION_VERSION && @may_manage_observation &&
          params[:assessment].blank? && !@assessment_request&.active? &&
          ![ request.headers["Purpose"], request.headers["Sec-Purpose"] ].compact.any? { |value| value.include?("prefetch") }
        @assessment_request = investigation.request(refresh: true, reassessment: @assessment, automatic: true) || @assessment_request
      end
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
    if params[:reassess] == "1"
      current = @workspace.assessments(@workspace.surface(@observation)).find(params[:assessment_id])
      raise ActiveRecord::RecordNotFound unless assessment_matches_claims?(current, @observation)

      RecordingResolution::Investigation.new(current_user, @observation).request(refresh: true, reassessment: current)
      return redirect_to resolution_surface_path(@observation), status: :see_other
    end

    manual = params[:manual_mbid].to_s.strip.presence
    if manual && !Clients::Musicbrainz::MBID.match?(manual)
      return redirect_to resolution_surface_path(@observation), alert: "Enter a MusicBrainz recording identifier.", status: :see_other
    end
    provenance_mbid = params[:provenance_mbid].presence
    if provenance_mbid
      assessment = @workspace.assessments(@workspace.surface(@observation)).find(params[:assessment_id])
      unless assessment_matches_claims?(assessment, @observation) &&
          RecordingResolution::ReleaseProvenance.checked_recording?(assessment.evidence, provenance_mbid)
        return redirect_to resolution_surface_path(@observation), alert: "Select a recording from a checked edition.", status: :see_other
      end
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
    RecordingResolution::Investigation.new(current_user, @observation).request(refresh: true, manual_mbid: manual, release_mbid:, provenance_mbid:, provenance_assessment_id: assessment&.id)
    redirect_to resolution_surface_path(@observation, play: params[:play].presence, candidate: params[:candidate].presence,
      source_recording: provenance_mbid, anchor: ("release-provenance" if provenance_mbid)), status: :see_other
  end

  def decide
    scope = { "surface" => :surface, "scrobble" => :scrobble }.fetch(params[:scope]) { raise ArgumentError }
    mode = (params[:construct_release].present? ? "resolved" : params[:mode]).presence_in(%w[resolved unresolved inherit]) || raise(ArgumentError)
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
      if mode == "resolved"
        RecordingSourceDecision.lock!
        if params[:resolution_plan].present?
          if params[:latest_release_review] == "1"
            claims = target.payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
            group_ids = RecordingResolution::Group.where(claims:).select(:id)
            latest = @workspace.assessments(surface).where(group_id: group_ids)
              .reorder(Arel.sql("(evidence->>'partial' IS NOT DISTINCT FROM 'true') ASC"), id: :desc).first
            raise ActiveRecord::StaleObjectError.new(target, "confirm current release evidence") unless latest == assessment
          end
          plan = CanonicalCatalog::ResolutionPlan.new(assessment, params[:recording_mbid], affected_count(target, surface, scope))
          unless ActiveSupport::SecurityUtils.secure_compare(plan.fingerprint, params[:resolution_plan].to_s) &&
              (plan.proposals.empty? ? params[:construct_release].blank? : plan.proposals.any? { |proposal| plan.edition_id(proposal) == params[:construct_release] })
            raise ActiveRecord::StaleObjectError.new(target, "confirm resolution preview")
          end
        end
        identity = plan&.identity
        if params[:identity_signature].present?
          identity ||= CanonicalCatalog::RecordingIdentity.new(assessment, params[:recording_mbid])
          unless ActiveSupport::SecurityUtils.secure_compare(identity.fingerprint, params[:identity_signature].to_s)
            raise ActiveRecord::StaleObjectError.new(target, "confirm recording identity")
          end
        end
        recording, context = selection(assessment, target, identity:)
      end
      previous = RecordingResolution::Ledger.effective(current_user).find(target.id)
      ranking = decision_ranking(assessment, surface, target)
      selected_rank = ranking&.find { |entry| entry["recording_mbid"] == params[:recording_mbid] }
      if code == "verified_identifier" && selected_rank&.dig("inputs", "recording_identifier", "state") != "positive"
        raise ArgumentError
      end
      if code == "corroborating_evidence" && selected_rank&.dig("inputs", "edition_slot", "state") != "positive"
        raise ArgumentError
      end
      metadata = { "reason_code" => code, "comment" => comment, "scoring_version" => ranking&.first&.fetch("version"),
        "candidate_scores" => ranking&.map { |row| row.slice("recording_mbid", "score") },
        "previous_effective_recording_id" => previous.effective_recording_id, "previous_effective_decision_id" => previous.effective_recording_decision_id,
        "affected_scope" => scope.to_s, "source_recording_mbid" => (params[:recording_mbid] if recording),
        "review_snapshot" => RecordingResolution::ReviewSnapshot.capture(assessment:, ranking: ranking || [],
          feedback: { "resolved" => "selected", "unresolved" => "unresolved", "inherit" => "inherit" }.fetch(mode),
          candidate_mbid: (params[:recording_mbid] if recording), affected_count: affected_count(target, surface, scope)) }.compact
      RecordingResolution::Ledger.record!(listener: current_user, scrobble: target, scope:, mode:, reason:, recording:,
        assessment:, metadata:, expected_head: params[:head].presence&.then { |value| Integer(value) })
      if recording
        request = CatalogImport.request!(CatalogImport::RECORDING_METADATA, recording.id, context)
        if scope == :surface && params[:construct_release].present?
          construct_reviewed_release!(assessment, recording, plan:, identity:)
        end
      end
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

  def retain_configuration
    assessment = @workspace.assessments(@workspace.surface(@observation)).find(params[:assessment_id])
    raise ActiveRecord::RecordNotFound unless assessment_matches_claims?(assessment, @observation)

    release, edition = configurations_for(assessment).find do |_, data|
      data["id"] == params[:edition_mbid]
    end || raise(ActiveRecord::RecordNotFound)
    release.with_lock do
      ReleaseConfiguration.retain!(release, edition, provenance: {
        "assessment_id" => assessment.id, "assessment_digest" => assessment.digest
      })
    end
    redirect_to release_path(release), notice: "Verified source configuration retained.", status: :see_other
  rescue CanonicalCatalog::Store::Unverified => error
    redirect_to resolution_surface_path(@observation, section: "evidence"), alert: error.message, status: :see_other
  end

  def select_reviewed_configuration
    assessment = @workspace.assessments(@workspace.surface(@observation)).find(params[:assessment_id])
    raise ActiveRecord::RecordNotFound unless assessment_matches_claims?(assessment, @observation)

    review = RecordingResolution::ReleaseReview.new(assessment.evidence)
    raise ActiveRecord::RecordNotFound unless review.policy

    edition = review.configurations.find { |item| item.data["id"] == params[:edition_mbid] }
    raise ActiveRecord::RecordNotFound unless edition

    release = current_user.with_lock do
      RecordingSourceDecision.lock!
      records = Release.where(release_group_mbid: review.group).limit(2).to_a
      raise CanonicalCatalog::Store::Unverified, "Review conflicting catalog releases first." if records.many?

      parent = records.first
      if parent.nil? && params[:admit] == "1"
        request = CatalogImport.create!(kind: "reviewed_configuration_admission", state: "imported",
          entity_id: assessment.id, due_at: Time.current, context: { reviewer_id: current_user.id, assessment_id: assessment.id })
        evidence = Struct.new(:provenance).new(Array(assessment.evidence["requests"]))
        parent = CanonicalCatalog::Store.new(request, evidence).release(edition.data, edition.slots, strict_collection: true)
      end
      raise CanonicalCatalog::Store::Unverified, "Admit an album configuration before choosing a preference." unless parent

      snapshot = ReleaseConfiguration.retain!(parent, edition.data,
        provenance: { "assessment_id" => assessment.id, "assessment_digest" => assessment.digest })
      ReleaseConfigurationDecision.select!(current_user, parent, snapshot)
      parent
    end
    redirect_to release_path(release), notice: "Release configuration selected.", status: :see_other
  rescue CanonicalCatalog::Store::Unverified => error
    redirect_to resolution_surface_path(@observation), alert: error.message, status: :see_other
  end

  def admit_adjacent_release
    assessments = @workspace.assessments(@workspace.surface(@observation))
    assessment = assessments.find(params[:assessment_id])
    raise ActiveRecord::RecordNotFound unless assessment_matches_claims?(assessment, @observation)

    release = Release.transaction do
      RecordingSourceDecision.lock!
      latest = assessments.where(group_id: assessment.group_id).reorder(id: :desc).first
      raise CanonicalCatalog::Store::Unverified, "Investigation changed. Review the latest evidence." if latest != assessment

      source, edition = adjacent_programs_for(assessment).find do |mbid, data|
        mbid == params[:recording_mbid] && data["id"] == params[:edition_mbid]
      end || raise(ActiveRecord::RecordNotFound)
      verified = CanonicalCatalog::Edition.new(edition, edition.fetch("id"), recording_mbid: source)
      history = assessment.evidence.fetch("additional_recording_publications", {}).fetch(source, assessment.evidence)
      review = CatalogImport.create!(kind: "adjacent_release_admission", state: "imported", entity_id: assessment.id,
        due_at: Time.current, context: { reviewer_id: current_user.id, assessment_id: assessment.id,
          assessment_digest: assessment.digest, source_recording_mbid: source, edition_mbid: edition.fetch("id") })
      provenance = Struct.new(:provenance).new(Array(history["requests"]))
      CanonicalCatalog::Store.new(review, provenance).release(edition, verified.slots, strict_collection: true)
    end
    redirect_to release_path(release), notice: "Adjacent release admitted.", status: :see_other
  rescue CanonicalCatalog::Store::Unverified => error
    redirect_to resolution_surface_path(@observation, section: "evidence"), alert: error.message, status: :see_other
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

  def adjacent_programs_for(assessment)
    histories = assessment.evidence.fetch("additional_recording_publications", {})
    retained_groups = Array(assessment.evidence["construction_editions"]).filter_map { |data| data.dig("release-group", "id") }
    programs = histories.flat_map do |mbid, history|
      Array(history["adjacent_programs"]).filter_map do |edition|
        group = edition.dig("release-group", "id")
        next if retained_groups.include?(group) || history.dig("exact_recording", "id") != mbid
        next unless CanonicalCatalog::Edition.original_context?(edition) && !CanonicalCatalog::Edition.mispressing?(edition)
        next unless Array(history["releases"]).any? { |row| row["id"] == edition["id"] && row["slots"].present? }

        [ mbid, edition ]
      end
    end
    review = RecordingResolution::ReleaseReview.new(assessment.evidence)
    if review.policy
      programs += review.programs.map { |edition, matches| [ matches.first.fetch(:source_recording_mbid), edition.data ] }
    end
    known = Release.where(release_group_mbid: programs.map { |_, edition| edition.dig("release-group", "id") }).pluck(:release_group_mbid).to_set
    programs.reject { |_, edition| known.include?(edition.dig("release-group", "id")) }
      .uniq { |_, edition| edition.fetch("id") }
  end

  def configurations_for(assessment)
    editions = Array(assessment.evidence["construction_editions"])
    groups = editions.filter_map { |data| data.dig("release-group", "id") }.uniq
    releases = Release.where(release_group_mbid: groups).where.not(catalog_verified_at: nil).group_by(&:release_group_mbid)
    editions.filter_map do |data|
      matching = releases.fetch(data.dig("release-group", "id"), [])
      next unless matching.one? && data["status"] == "Official" && !CanonicalCatalog::Edition.mispressing?(data)

      CanonicalCatalog::Edition.new(data, CanonicalCatalog::Store.mbid!(data["id"]))
      [ matching.first, data ]
    rescue CanonicalCatalog::Store::Unverified
      nil
    end
  end

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

  def construct_reviewed_release!(assessment, recording, plan:, identity:)
    recording.lock!
    choices = plan&.proposals || CanonicalCatalog::ReviewedConstruction.resolution_choices(
      assessment, params[:recording_mbid], recording, source_ids: identity&.source_ids || [ params[:recording_mbid] ]).flatten
    proposal = choices.find { |item| item.construction.base.data["id"] == params[:construct_release] }
    if proposal.nil?
      # A previously rendered form may still submit the release group.
      compatible = choices.select { |item| item.construction.base.data.dig("release-group", "id") == params[:construct_release] }
      proposal = compatible.first if compatible.one?
    end
    raise ActiveRecord::StaleObjectError.new(recording, "construct release") unless proposal

    existing = proposal.existing
    if existing
      existing.lock!
      expected_head = params[:construction_heads]&.[](proposal.construction.base.data["id"]) || params[:construction_head]
      unless CanonicalCatalog::ReviewedConstruction.head(existing) == expected_head
        raise ActiveRecord::StaleObjectError.new(existing, "correct release")
      end
    end
    return unless CanonicalCatalog::ReviewedConstruction.needs_review?(proposal, recording)

    review = CatalogImport.create!(kind: "release_construction", entity_id: recording.id, due_at: Time.current,
      state: "imported", context: { "assessment_id" => assessment.id, "reviewer_id" => current_user.id })
    CanonicalCatalog::ReviewedConstruction.apply!(proposal, review, assessment, corrected_release: existing)
  end

  def selection(assessment, target, identity:)
    candidate = RecordingResolution::Workspace.candidate_evidence(assessment.evidence.except("verified_recording"))
      .find { |item| item["id"] == params[:recording_mbid] }
    raise ArgumentError unless candidate
    if RecordingResolution::Ranking.call(@workspace.surface(target), assessment.evidence, source_hints: true)
        .none? { |entry| entry["recording_mbid"] == candidate["id"] }
      raise ArgumentError
    end

    context = { "assessment_id" => assessment.id, "source_recording_mbid" => candidate.fetch("id") }
    record = identity ? identity.apply!(assessment, current_user) : CanonicalCatalog::Store.recording!(candidate)
    [ record, context ]
  end
end
