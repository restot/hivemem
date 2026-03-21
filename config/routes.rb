Rails.application.routes.draw do
  # MCP endpoint (streamable HTTP)
  match "/mcp", to: "mcp#handle", via: [:get, :post, :delete]

  # Health check
  get "/health", to: "health#show"
  get "up" => "rails/health#show", as: :rails_health_check
end
