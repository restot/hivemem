class HivememReadTool < MCP::Tool
  description "Fetch a full knowledge record by shortlink. Returns all fields including content."

  input_schema(
    properties: {
      shortlink: { type: "string", description: "Record shortlink (e.g. hm-abc1234)" }
    },
    required: ["shortlink"]
  )

  class << self
    def call(shortlink:, server_context: {})
      record = KnowledgeRecord.find_by_shortlink!(shortlink)
      MCP::Tool::Response.new([{ type: "text", text: record.as_full_record.to_json }])
    rescue ActiveRecord::RecordNotFound
      raise MCP::Tool::Error, "Record not found: #{shortlink}"
    end
  end
end
