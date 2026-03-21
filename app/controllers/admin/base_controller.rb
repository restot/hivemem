module Admin
  class BaseController < ActionController::Base
    # Full MVC controller (not API-only) so we can render HTML views
    layout "admin"

    before_action :authenticate!

    private

    def authenticate!
      token = ENV.fetch("HIVEMEM_AUTH_TOKEN", nil)
      return if token.blank? # no auth configured = open

      provided = request.headers["Authorization"]&.delete_prefix("Bearer ")
      provided ||= params[:token]
      provided ||= session[:admin_token]

      if provided == token
        session[:admin_token] = token
      else
        render plain: "Unauthorized", status: :unauthorized
      end
    end
  end
end
