Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  resource :session, only: %i[new create destroy]
  root "home#show"
end
