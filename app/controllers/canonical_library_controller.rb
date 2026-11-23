class CanonicalLibraryController < ApplicationController
  MODELS = { "artists" => Artist, "releases" => Release, "recordings" => Recording }.freeze
  PAGE = 30
  include PublishedProfile
  skip_before_action :require_authentication,
    if: -> { public_profile_request? && %w[index show].include?(action_name) }
  before_action :section

  def index
    @query = params[:q].to_s.strip.first(100)
    records = catalog_scope
    field = @model == Artist ? "name" : "title"
    records = records.where("#{field} ILIKE ?", "%#{@model.sanitize_sql_like(@query)}%") if @query.present?
    cursor = params[:before].to_i
    @entries = if @model == Recording
      records = records.where("id < ?", cursor) if cursor.positive?
      with_artist_credits(records.order(id: :desc)).limit(PAGE + 1).to_a
    else
      listening_index_page(records, field, cursor)
    end
    @next_page = @entries.pop && @entries.last.id if @entries.size > PAGE
    @musical_identities, @inherited_musical_identities = MusicalIdentityDecision.presentation_for(@entries)
  end

  def show
    @entry = with_artist_credits(catalog_scope).find(params[:id])
    @archive_available = @public_profile || current_user.user_lastfm_accounts.active.exists?
    unless @public_profile
      @may_import = current_user.managed_archive_grants.exists?
      @import_request = CatalogImport.latest(@section.singularize, @entry.id)
      @revision = CatalogRevision.where(entity_type: @model.name, entity_id: @entry.id).order(id: :desc).first
    end

    case @entry
    when Artist
      @geography = CatalogRevision.where(entity_type: CanonicalCatalog::ArtistGeography::ENTITY_TYPE, entity_id: @entry.id)
        .order(id: :desc).first
      load_artist_listening
    when Release
      @ranked_release = ReleaseRanking.new(current_user, [ @entry ]).include?(@entry) unless @public_profile
      base_slots = @entry.catalog_track_slots.base_sequence
      slots = base_slots.order(:medium, :position)
      cursor = slots.find_by(id: params[:after_track]) if params[:after_track].present?
      if cursor
        @track_offset = slots.where("(medium, position) <= (?, ?)", cursor.medium, cursor.position).count
        slots = slots.where("(medium, position) > (?, ?)", cursor.medium, cursor.position)
      end
      @slots = slots.includes(:recording).limit(101).to_a
      @additional_appearances = @entry.catalog_track_slots.additional_appearances
        .order(:appearance_date, :edition_mbid, :medium, :position).includes(:recording).limit(200)
      @additional_edition_evidence = additional_edition_evidence
      @next_track = @slots.pop && @slots.last.id if @slots.size > 100
      if @slots.empty? && !@public_profile && !cursor
        legacy_slots = @entry.release_recordings.order(:position, :id)
        legacy_cursor = legacy_slots.find_by(id: params[:after_legacy_track]) if params[:after_legacy_track].present?
        if legacy_cursor
          legacy_slots = legacy_slots.where("(position, id) > (?, ?)", legacy_cursor.position, legacy_cursor.id)
        end
        @legacy_slots = legacy_slots.includes(recording: { recording_artists: :artist }).limit(101).to_a
        @next_legacy_track = @legacy_slots.pop && @legacy_slots.last.id if @legacy_slots.size > 100
      end
      @counted_tracks = ReleaseTrackListeningDecision.included_memberships(listening_user, [ @entry.id ])
        .pluck(:recording_id).to_set
      @track_counts = recording_plays((base_slots.distinct.pluck(:recording_id).to_set & @counted_tracks).to_a)
        .group("effective_resolution.recording_id").count(:id)
      other_ids = Array(params[:with_release]).first(PAGE).map { |id| Integer(id, exception: false) }.compact
      @activity_releases = catalog_scope.where(id: [ @entry.id, *other_ids ]).order(:id).to_a
      member_ids = ReleaseTrackListeningDecision.included_memberships(listening_user, @activity_releases.map(&:id)).pluck(:recording_id)
      release_plays = recording_plays(member_ids)
      @listening_total = CatalogListening.new(release_plays).total
      @observation_count = @listening_total.plays
      @timeline = CatalogListening.new(release_plays).timeline("all") if @archive_available
      @plays = ListeningPage.chronological(release_plays, before: params[:before_play]).limit(PAGE + 1).to_a
      @next_release_play = @plays.pop && @plays.last.id if @plays.size > PAGE
      @activity_recordings = Recording.where(id: @plays.map(&:effective_recording_id)).index_by(&:id)
    when Recording
      @chronology = CanonicalCatalog::RecordingChronology.latest(@entry)
      chronology_revisions = CatalogRevision.where(entity_type: "Recording", entity_id: @entry.id).order(id: :desc)
      @verified_first_release = chronology_revisions.where("evidence ? 'verified_publication'")
        .pick(Arel.sql("evidence->'verified_publication'->>'date'"))
      @first_release_claim = chronology_revisions
        .where("evidence->'musicbrainz' ? 'first-release-date'")
        .pick(Arel.sql("evidence->'musicbrainz'->>'first-release-date'"))
      @releases = @entry.admitted_releases.order(:title, :id).includes(release_artists: :artist)
      @releases = @releases.merge(@profile_catalog.releases) if @public_profile
      cursor = @releases.find_by(id: params[:after_appearance]) if params[:after_appearance].present?
      if cursor
        @releases = @releases.where("(releases.title, releases.id) > (?, ?)", cursor.title, cursor.id)
      end
      @releases = @releases.limit(PAGE + 1).to_a
      @next_appearance = @releases.pop && @releases.last.id if @releases.size > PAGE
      plays = recording_plays([ @entry.id ])
      listening = CatalogListening.new(plays)
      @listening_total = listening.total
      @timeline = listening.timeline("all") if @archive_available
      @observation_count = @listening_total.plays
      if @public_profile
        plays = ListeningPage.chronological(plays, before: params[:before])
      else
        plays = plays.where("scrobbles.id < ?", params[:before].to_i) if params[:before].to_i.positive?
        plays = plays.order(id: :desc)
      end
      @plays = plays.limit(PAGE + 1).to_a
      @next_page = @plays.pop && @plays.last.id if @plays.size > PAGE
    end
    related = [ *@recording_rows&.map(&:first), *@release_rows&.map(&:first), *@slots&.map(&:recording), *@additional_appearances&.map(&:recording), *@releases ]
    @musical_identities, @inherited_musical_identities = MusicalIdentityDecision.presentation_for([ @entry, *related ])
    @may_edit_identity = @may_import && (@entry.is_a?(Release) ? @entry.catalog_verified_at.present? : Clients::Musicbrainz::MBID.match?(@entry.mbid.to_s))
  end

  def ranking
    release = catalog_scope.find(params[:id])
    included = { "include" => true, "exclude" => false }.fetch(params[:decision]) { return head :unprocessable_entity }

    current_user.with_lock do
      latest = ReleaseRankingDecision.latest_for(current_user, [ release.id ])[release.id]
      ReleaseRankingDecision.create!(user: current_user, release:, included:) unless latest&.included == included
    end
    redirect_to release_path(release), status: :see_other
  end

  def track_listening
    release = Release.find(params[:id])
    recording = release.catalog_track_slots.find_by!(recording_id: params[:recording_id]).recording
    included = { "include" => true, "exclude" => false }.fetch(params[:decision]) { return head :unprocessable_entity }

    current_user.with_lock do
      decisions = ReleaseTrackListeningDecision.where(user: current_user, release:, recording:)
      decisions.create!(included:) unless decisions.order(id: :desc).first&.included == included
    end
    redirect_to release_path(release, track_preferences: "1", anchor: "release-track-listening"), status: :see_other
  end

  def musical_identity
    entry = catalog_scope.find(params[:id])
    verified = entry.is_a?(Release) ? entry.catalog_verified_at.present? : Clients::Musicbrainz::MBID.match?(entry.mbid.to_s)
    return head :forbidden unless verified && current_user.managed_archive_grants.exists?

    input = params.expect(musical_identity: [ :head, :rationale, :inherit, colors: [] ])
    entry.with_lock do
      previous = MusicalIdentityDecision.latest_for([ entry ])[[ entry.class.name, entry.id ]]
      if previous&.id.to_s != input[:head].to_s
        flash[:alert] = "Musical identity changed. Review the latest assignment before editing."
      else
        inherit = input[:inherit] == "1"
        decision = MusicalIdentityDecision.new(entity: entry, user: current_user,
          colors: inherit ? [] : Array(input[:colors]).reject(&:blank?), rationale: inherit ? nil : input[:rationale])
        if decision.save
          flash[:notice] = "Musical identity saved."
        else
          flash[:alert] = decision.errors.full_messages.to_sentence
        end
      end
    end
    redirect_to helpers.catalog_entry_path(entry, anchor: "guide-assignment"), status: :see_other
  end

  def chronology
    recording = Recording.find(params[:id])
    unless current_user.managed_archive_grants.exists? && Clients::Musicbrainz::MBID.match?(recording.mbid.to_s)
      return head :forbidden
    end

    input = params.expect(chronology: [ :start_date, :end_date, :source, :head ])
    CanonicalCatalog::RecordingChronology.record!(recording, current_user, **input.to_h.symbolize_keys)
    redirect_to recording_path(recording, anchor: "recording-chronology"), notice: "Recording date saved.", status: :see_other
  rescue ArgumentError, ActiveRecord::StaleObjectError => error
    redirect_to recording_path(recording, anchor: "recording-chronology"), alert: error.message, status: :see_other
  end

  def import
    return head :forbidden unless current_user.managed_archive_grants.exists?

    entry = @model.find(params[:id])
    kind = @section.singularize
    request = CatalogImport.request!(kind, entry.id)
    request.dispatch
    redirect_to polymorphic_path(entry), notice: "Import requested.", status: :see_other
  end

  private

  def additional_edition_evidence
    tracklist = RecordingResolution::ReleaseTracklist.new(@entry)
    Array(tracklist.revision.evidence["checked_recording_appearances"]).flat_map do |edition|
      next [] unless Clients::Musicbrainz::MBID.match?(edition["id"].to_s)

      Array(edition["additional_tracks"]).filter_map do |track|
        mbid = track["recording_mbid"]
        next unless Clients::Musicbrainz::MBID.match?(mbid.to_s) && track["title"].present?

        [ mbid, track["title"], edition["id"], track["edition_appearance_date"] ]
      end
    end
  rescue ArgumentError
    []
  end

  def listening_index_page(records, field, cursor)
    memberships, entity_key = if @model == Artist
      [ RecordingArtist.where(artist_id: records.select(:id)), :artist_id ]
    else
      [ ReleaseTrackListeningDecision.included_memberships(listening_user, records.select(:id)), :release_id ]
    end
    pairs = memberships.distinct.pluck(entity_key, :recording_id)
    by_recording = CatalogListening.new(recording_plays(pairs.map(&:last).uniq)).by_recording
    @index_listening = Hash.new(CatalogListening::EMPTY)
    pairs.each do |entity_id, recording_id|
      @index_listening[entity_id] += by_recording.fetch(recording_id, CatalogListening::EMPTY)
    end

    ordered = records.pluck(:id, field).sort_by do |id, name|
      [ -@index_listening[id].milliseconds, name.downcase, id ]
    end.map(&:first)
    @index_time_max = @index_listening[ordered.first].milliseconds
    offset = ordered.index(cursor)
    ids = ordered.slice(offset ? offset + 1 : 0, PAGE + 1)
    entries = with_artist_credits(records.where(id: ids)).index_by(&:id)
    ids.filter_map { |id| entries[id] }
  end

  def load_artist_listening
    recordings = Recording.where(id: @entry.recording_artists.select(:recording_id))
    recordings = recordings.merge(@profile_catalog.recordings) if @public_profile
    releases = Release.where(id: @entry.release_artists.select(:release_id)).or(
      Release.where(id: CatalogTrackSlot.where(recording_id: recordings.select(:id)).select(:release_id)))
    releases = releases.merge(@profile_catalog.releases) if @public_profile
    releases = releases.to_a
    ranking = ReleaseRanking.new(@public_profile&.owner || current_user, releases)
    releases.select! { |release| ranking.include?(release) }
    memberships = ReleaseTrackListeningDecision.included_memberships(listening_user, releases.map(&:id)).pluck(:release_id, :recording_id)
      .group_by(&:first)
    records = recordings.to_a
    artist_listening = CatalogListening.new(recording_plays(records.map(&:id)))
    stats = artist_listening.by_recording
    @listening_total = stats.values.reduce(CatalogListening::EMPTY, :+)
    @history_range = params[:range].to_s
    @history_range = "all" unless CatalogListening::RANGES.key?(@history_range)
    @timeline = artist_listening.timeline(@history_range)
    @recording_count = records.size
    @recording_sort = %w[plays title length recent].find { |sort| sort == params[:recording_sort] } || "plays"
    @recording_rows = records.map { |record| [ record, stats.fetch(record.id, CatalogListening::EMPTY) ] }
    @recording_rows.sort_by! do |record, totals|
      key = case @recording_sort
      when "title" then record.title.downcase
      when "length" then -(record.duration_ms || 0)
      when "recent" then -(totals.last_played&.to_i || 0)
      else -totals.plays
      end
      [ key, record.title.downcase, record.id ]
    end
    @play_bar_max = @recording_rows.map { |_, totals| totals.plays }.max.to_i
    @recording_page = params[:recording_page].to_i.clamp(0, [ (@recording_count - 1) / 10, 0 ].max)
    @recording_rows = @recording_rows.slice(@recording_page * 10, 10) || []

    external_ids = memberships.values.flatten(1).map(&:last).uniq - records.map(&:id)
    stats.merge!(CatalogListening.new(recording_plays(external_ids)).by_recording) if external_ids.any?
    @release_rows = releases.map do |release|
      totals = memberships.fetch(release.id, []).map { |_, id| stats.fetch(id, CatalogListening::EMPTY) }
      [ release, totals.reduce(CatalogListening::EMPTY, :+) ]
    end.sort_by { |release, totals| [ -totals.milliseconds, release.title.downcase, release.id ] }
    @time_bar_max = @release_rows.first&.last&.milliseconds.to_i
  end

  def section
    @section = request.path_parameters.fetch(:section).to_s
    @model = MODELS.fetch(@section)
  end

  def with_artist_credits(records)
    case @section
    when "recordings" then records.includes(recording_artists: :artist)
    when "releases" then records.includes(release_artists: :artist)
    else records
    end
  end

  def catalog_scope
    return @model.all unless @profile_catalog

    case @section
    when "artists" then @profile_catalog.artists
    when "releases" then @profile_catalog.releases
    when "recordings" then @profile_catalog.recordings
    end
  end

  def listening_user
    @public_profile&.owner || current_user
  end

  def recording_plays(ids)
    if @profile_catalog
      @profile_catalog.catalog_plays.where("effective_resolution.recording_id IN (?)", ids.presence || [ nil ])
    else
      RecordingResolution::Ledger.for_recordings(current_user, ids)
    end
  end
end
