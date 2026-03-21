class McpController < ApplicationController
  before_action :authenticate_token

  def self.auth_token
    @auth_token ||= begin
      token = ENV["HIVEMEM_AUTH_TOKEN"].presence || SecureRandom.hex(32)
      if ENV["HIVEMEM_AUTH_TOKEN"].blank?
        $stderr.puts "[hivemem] No HIVEMEM_AUTH_TOKEN set. Generated token: #{token}"
      end
      token
    end
  end

  TOOLS = [
    HivememSearchTool,
    HivememReadTool,
    HivememWriteTool,
    HivememUpdateTool,
    HivememDeleteTool
  ].freeze

  def handle
    server = MCP::Server.new(
      name: "hivemem",
      version: "1.0.0",
      tools: TOOLS
    )
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
    server.transport = transport
    status, headers, body = transport.handle_request(request)
    response_body = body&.first
    if response_body.nil?
      head status, headers: headers
    else
      render json: response_body, status: status, headers: headers
    end
  end

  private

  def authenticate_token
    expected = self.class.auth_token

    provided = request.headers["Authorization"]&.delete_prefix("Bearer ")
    return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
