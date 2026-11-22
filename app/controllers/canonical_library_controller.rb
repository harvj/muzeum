class CanonicalLibraryController < ApplicationController
  MODELS = { "artists" => Artist, "releases" => Release, "recordings" => Recording }.freeze
  PAGE = 30
  include PublishedProfile
  skip_before_action :require_authentication,
    if: -> { public_profile_request? && %w[index show].include?(action_name) }
  before_action :section

  def index
    @query = params[:q].to_s.strip.first(100)
    records = catalog_scope.order(id: :desc)
    records = records.where("id < ?", params[:before].to_i) if params[:before].to_i.positive?
    field = @model == Artist ? "name" : "title"
    records = records.where("#{field} ILIKE ?", "%#{@model.sanitize_sql_like(@query)}%") if @query.present?
    @entries = with_artist_credits(records).limit(PAGE + 1).to_a
    @next_page = @entries.pop && @entries.last.id if @entries.size > PAGE
    if @model == Artist
      @geographies = CatalogRevision.where(entity_type: CanonicalCatalog::ArtistGeography::ENTITY_TYPE, entity_id: @entries.map(&:id))
        .select("DISTINCT ON (entity_id) entity_id, evidence").order(:entity_id, id: :desc).index_by(&:entity_id)
    end
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
      slots = @entry.catalog_track_slots.base_sequence.order(:medium, :position)
      cursor = slots.find_by(id: params[:after_track]) if params[:after_track].present?
      if cursor
        @track_offset = slots.where("(medium, position) <= (?, ?)", cursor.medium, cursor.position).count
        slots = slots.where("(medium, position) > (?, ?)", cursor.medium, cursor.position)
      end
      @slots = slots.includes(:recording).limit(101).to_a
      @additional_appearances = @entry.catalog_track_slots.additional_appearances
        .order(:appearance_date, :edition_mbid, :medium, :position).includes(:recording)
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
      recording_ids = @slots.map(&:recording_id)
      @track_counts = recording_plays(recording_ids)
        .group("effective_resolution.recording_id").count(:id)
      other_ids = Array(params[:with_release]).first(PAGE).map { |id| Integer(id, exception: false) }.compact
      @activity_releases = catalog_scope.where(id: [ @entry.id, *other_ids ]).order(:id).to_a
      member_ids = Release.member_recording_ids(@activity_releases.map(&:id))
      release_plays = recording_plays(member_ids)
      @listening_total = CatalogListening.new(release_plays).total
      @observation_count = @listening_total.plays
      @plays = ListeningPage.chronological(release_plays, before: params[:before_play]).limit(PAGE + 1).to_a
      @next_release_play = @plays.pop && @plays.last.id if @plays.size > PAGE
      @activity_recordings = Recording.where(id: @plays.map(&:effective_recording_id)).index_by(&:id)
    when Recording
      if CatalogTrackSlot.edition_slots_supported?
        @recording_chronology = CatalogRevision.where(entity_type: "RecordingChronology", entity_id: @entry.id)
          .order(id: :desc).pick(:evidence) || {}
        @first_release_claim = CatalogRevision.where(entity_type: "Recording", entity_id: @entry.id)
          .where("evidence->'musicbrainz' ? 'first-release-date'").order(id: :desc)
          .pick(Arel.sql("evidence->'musicbrainz'->>'first-release-date'"))
      end
      @releases = @entry.admitted_releases.order(:title, :id).includes(release_artists: :artist)
      @releases = @releases.merge(@profile_catalog.releases) if @public_profile
      cursor = @releases.find_by(id: params[:after_appearance]) if params[:after_appearance].present?
      if cursor
        @releases = @releases.where("(releases.title, releases.id) > (?, ?)", cursor.title, cursor.id)
      end
      @releases = @releases.limit(PAGE + 1).to_a
      @next_appearance = @releases.pop && @releases.last.id if @releases.size > PAGE
      plays = recording_plays([ @entry.id ])
      @listening_total = CatalogListening.new(plays).total
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

  def load_artist_listening
    recordings = Recording.where(id: @entry.recording_artists.select(:recording_id))
    recordings = recordings.merge(@profile_catalog.recordings) if @public_profile
    releases = Release.where(id: @entry.release_artists.select(:release_id)).or(
      Release.where(id: CatalogTrackSlot.where(recording_id: recordings.select(:id)).select(:release_id)))
    releases = releases.merge(@profile_catalog.releases) if @public_profile
    memberships = CatalogTrackSlot.where(release_id: releases.select(:id)).distinct.pluck(:release_id, :recording_id)
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

  def recording_plays(ids)
    if @profile_catalog
      @profile_catalog.catalog_plays.where("effective_resolution.recording_id IN (?)", ids.presence || [ nil ])
    else
      RecordingResolution::Ledger.for_recordings(current_user, ids)
    end
  end
end
