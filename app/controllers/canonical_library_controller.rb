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
      @recordings = @entry.recordings.order(:title, :id).includes(recording_artists: :artist)
      @recordings = @recordings.merge(@profile_catalog.recordings) if @public_profile
      performed_on = CatalogTrackSlot.where(recording_id: @entry.recording_artists.select(:recording_id)).select(:release_id)
      @releases = Release.where(id: @entry.release_artists.select(:release_id)).or(Release.where(id: performed_on)).order(:title, :id).includes(release_artists: :artist)
      @releases = @releases.merge(@profile_catalog.releases) if @public_profile
    when Release
      @slots = @entry.catalog_track_slots.order(:medium, :position).includes(:recording)
      @legacy_slots = @entry.release_recordings.order(:position).includes(:recording) if @slots.empty? && !@public_profile
      recording_ids = @slots.map(&:recording_id)
      @track_counts = effective.where("effective_resolution.recording_id IN (?)", recording_ids.presence || [ nil ])
        .group("effective_resolution.recording_id").count(:id)
    when Recording
      @releases = @entry.admitted_releases.order(:title, :id).includes(release_artists: :artist)
      @releases = @releases.merge(@profile_catalog.releases) if @public_profile
      plays = effective.where("effective_resolution.recording_id = ?", @entry.id)
      @observation_count = plays.count(:id)
      @unresolved_available = !@public_profile && @archive_available && effective.where("effective_resolution.recording_id IS NULL").exists?
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

  def effective
    @profile_catalog ? @profile_catalog.catalog_plays : RecordingResolution::Ledger.effective(current_user)
  end
end
