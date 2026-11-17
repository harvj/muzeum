Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  resource :session, only: %i[new create destroy]
  get "oidc/callback", to: "sessions#callback"
  resource :lastfm_account, only: :update
  resources :imports, only: :create
  root "home#show"
end
