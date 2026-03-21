Rails.application.routes.draw do
  # MCP endpoint (streamable HTTP)
  match "/mcp", to: "mcp#handle", via: [ :get, :post, :delete ]

  # Health check
  get "/health", to: "health#show"
  get "up" => "rails/health#show", as: :rails_health_check

  # Admin UI
  namespace :admin do
    root to: "dashboard#show"
    resources :records, only: [ :index, :show, :destroy ], param: :id
  end
end
