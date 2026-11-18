Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  resource :session, only: %i[new create destroy]
  get "oidc/callback", to: "sessions#callback"
  resource :lastfm_account, only: :update
  resources :imports, only: :create
  get "dashboard", to: "home#updates", as: :dashboard_updates
  %i[artists releases recordings].each do |section|
    resources section, only: %i[index show], controller: "canonical_library", defaults: { section: } do
      post :import, on: :member
    end
  end
  resources :resolution_surfaces, path: "resolution", controller: "resolution_workspace", only: %i[index show] do
    post :investigate, on: :member
    post :decide, on: :member
    post :admit, on: :member
  end
  root "home#show"
end
