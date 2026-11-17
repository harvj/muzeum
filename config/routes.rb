Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  resource :session, only: %i[new create destroy]
  get "oidc/callback", to: "sessions#callback"
  resource :lastfm_account, only: :update
  resources :imports, only: :create
  get "dashboard", to: "home#updates", as: :dashboard_updates
  root "home#show"
end
