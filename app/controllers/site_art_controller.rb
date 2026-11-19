class SiteArtController < ActionController::API
  def show
    response.headers["Cache-Control"] = "no-store"
    render json: SiteArt.snapshot
  end
end
