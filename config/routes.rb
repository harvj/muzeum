Rails.application.routes.draw do
  get "application-shell", to: "application_shell#show", as: :application_shell
  get "site-art", to: "site_art#show"
  get "up" => "rails/health#show", as: :rails_health_check
  get "login", to: "sessions#login"
  resource :session, only: :destroy
  get "oidc/callback", to: "sessions#callback"
  resource :lastfm_account, only: :update
  resources :imports, only: :create
  get "archive", to: "home#show", as: :archive
  get "archive/summary", to: "home#summary", as: :archive_summary
  get "profiles/:profile", to: "public_profiles#show", as: :public_profile
  scope "profiles/:profile", as: :public_profile do
    %i[artists releases recordings].each do |section|
      resources section, only: %i[index show], controller: "canonical_library", defaults: { section: }
    end
  end
  get "dashboard", to: "home#updates", as: :dashboard_updates
  %i[artists releases recordings].each do |section|
    resources section, only: %i[index show], controller: "canonical_library", defaults: { section: } do
      post :import, on: :member
      patch :musical_identity, on: :member
      if section == :releases
        patch :ranking, on: :member
        patch :track_listening, on: :member
      end
      patch :chronology, on: :member if section == :recordings
    end
  end
  resources :resolution_surfaces, path: "resolution", controller: "resolution_workspace", only: %i[index show] do
    post :investigate, on: :member
    post :defer, on: :member
    post :decide, on: :member
    get :release_batch, on: :member
    post :confirm_release_batch, on: :member
  end
  root "landing#show"
end
