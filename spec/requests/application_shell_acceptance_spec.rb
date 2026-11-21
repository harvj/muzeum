require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/public_profile_fixture"

RSpec.describe "Disposable canonical-host Shell acceptance", type: :request do
  include Rails.application.routes.url_helpers
  include OidcFlow
  include PublicProfileFixture

  def app
    @shell_host_app ||= ActionDispatch::HostAuthorization.new(Rails.application, [ "muzeum.fm" ])
  end

  before do
    prepare_oidc
    ENV["OIDC_REDIRECT_URI"] = "https://muzeum.fm/oidc/callback"
    host! "muzeum.fm"
    https!
  end
  after { restore_oidc }

  def expect_public_shell
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('a.harvj-wordmark[href="https://muzeum.fm/"]')).to be_present
    expect(doc.at_css('header a[href="/login"]')&.text).to eq("Log In")
    expect(doc.at_css("header .harvj-session")).to be_nil
  end

  it "exercises the only registered host and the anonymous, public-profile and authenticated route classes" do
    production_config = Rails.root.join("config/environments/production.rb").read
    expect(production_config.scan(/^\s*config\.hosts = (.*)$/).flatten).to eq([ '[ "muzeum.fm" ]' ])
    host! "www.muzeum.fm"
    get root_path
    expect(response).to have_http_status(:forbidden)
    host! "muzeum.fm"

    fixture = listening_profile_fixture
    profile = fixture.fetch(:profile)
    get root_path
    expect_public_shell
    get "/up"
    expect(response).to have_http_status(:ok)
    get "/site-art"
    expect(response).to have_http_status(:ok)
    get application_shell_path
    expect(response).to have_http_status(:unauthorized)
    get public_profile_path(profile)
    expect(response).to have_http_status(:not_found)
    get archive_path
    expect(response).to redirect_to(root_path)

    authorize_fixture_publication(fixture)
    [ public_profile_path(profile), public_profile_artists_path(profile),
      public_profile_releases_path(profile), public_profile_recordings_path(profile),
      public_profile_artist_path(profile, fixture.fetch(:artist)),
      public_profile_release_path(profile, fixture.fetch(:album)),
      public_profile_recording_path(profile, fixture.fetch(:recording)) ].each do |path|
      get path
      expect_public_shell
      expect(Nokogiri::HTML(response.body).at_css('nav[aria-label="Public profile"]')).to be_present
    end

    @subject = fixture.fetch(:owner).oidc_subject
    finish_oidc
    [ archive_path, archive_summary_path, artists_path, releases_path, recordings_path,
      artist_path(fixture.fetch(:artist)), release_path(fixture.fetch(:album)), recording_path(fixture.fetch(:recording)),
      resolution_surfaces_path, resolution_surface_path(fixture.fetch(:resolved)) ].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("header .harvj-session")).to be_present
      expect(doc.at_css('nav[aria-label="Music library"] a[aria-current="page"]')).to be_present
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end
end
