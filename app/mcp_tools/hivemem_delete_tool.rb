class HivememDeleteTool < MCP::Tool
  description "Permanently delete a knowledge record by shortlink."

  input_schema(
    properties: {
      shortlink: { type: "string", description: "Record shortlink to delete" }
    },
    required: ["shortlink"]
  )

  class << self
    def call(shortlink:, server_context: {})
      record = KnowledgeRecord.find_by_shortlink!(shortlink)
      record.destroy!
      MCP::Tool::Response.new([{ type: "text", text: { deleted: shortlink }.to_json }])
    rescue ActiveRecord::RecordNotFound
      raise MCP::Tool::Error, "Record not found: #{shortlink}"
    end
  end
end
