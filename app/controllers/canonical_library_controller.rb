class CanonicalLibraryController < ApplicationController
  MODELS = { "artists" => Artist, "releases" => Release, "recordings" => Recording }.freeze
  PAGE = 30
  before_action :section

  def index
    @query = params[:q].to_s.strip.first(100)
    records = @model.order(id: :desc)
    records = records.where("id < ?", params[:before].to_i) if params[:before].to_i.positive?
    field = @model == Artist ? "name" : "title"
    records = records.where("#{field} ILIKE ?", "%#{@model.sanitize_sql_like(@query)}%") if @query.present?
    @entries = with_artist_credits(records).limit(PAGE + 1).to_a
    @next_page = @entries.pop && @entries.last.id if @entries.size > PAGE
  end

  def show
    @entry = with_artist_credits(@model).find(params[:id])
    @import_request = CatalogImport.latest(@section.singularize, @entry.id)
    @archive_available = current_user.user_lastfm_accounts.active.exists?
    @revision = CatalogRevision.where(entity_type: @model.name, entity_id: @entry.id).order(id: :desc).first

    case @entry
    when Artist
      @recordings = @entry.recordings.order(:title, :id).includes(recording_artists: :artist)
      performed_on = CatalogTrackSlot.where(recording_id: @entry.recording_artists.select(:recording_id)).select(:release_id)
      @releases = Release.where(id: @entry.release_artists.select(:release_id)).or(Release.where(id: performed_on)).order(:title, :id).includes(release_artists: :artist)
    when Release
      @slots = @entry.catalog_track_slots.order(:medium, :position).includes(:recording)
      @legacy_slots = @entry.release_recordings.order(:position).includes(:recording) if @slots.empty?
      recording_ids = @slots.map(&:recording_id)
      @track_counts = effective.where("effective_resolution.recording_id IN (?)", recording_ids.presence || [ nil ])
        .group("effective_resolution.recording_id").count(:id)
    when Recording
      @releases = @entry.admitted_releases.order(:title, :id).includes(release_artists: :artist)
      plays = effective.where("effective_resolution.recording_id = ?", @entry.id)
      @observation_count = plays.count(:id)
      @unresolved_available = @archive_available && effective.where("effective_resolution.recording_id IS NULL").exists?
      plays = plays.where("scrobbles.id < ?", params[:before].to_i) if params[:before].to_i.positive?
      @plays = plays.order(id: :desc).limit(PAGE + 1).to_a
      @next_page = @plays.pop && @plays.last.id if @plays.size > PAGE
    end
  end

  def import
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

  def effective
    RecordingResolution::Ledger.effective(current_user)
  end
end
