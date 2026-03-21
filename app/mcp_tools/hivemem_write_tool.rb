class HivememWriteTool < MCP::Tool
  description "Create a new knowledge record. Returns the created record with generated shortlink."

  input_schema(
    properties: {
      title: { type: "string", description: "Short descriptive title" },
      content: { type: "string", description: "Full record content" },
      knowledge_type: { type: "string", description: "One of: convention, pattern, decision, failure, reference, guide" },
      project: { type: "string", description: "Project identifier (e.g. telegram-bot, hivemem)" },
      summary: { type: "string", description: "1-3 sentence summary for search results" },
      tags: { type: "array", items: { type: "string" }, description: "Free-form tags" },
      created_by: { type: "string", description: "Actor identifier" }
    },
    required: %w[title content knowledge_type project]
  )

  class << self
    def call(title:, content:, knowledge_type:, project:, summary: nil, tags: [], created_by: nil, server_context: {})
      record = KnowledgeRecord.create!(
        title: title,
        content: content,
        knowledge_type: knowledge_type,
        project: project,
        summary: summary,
        tags: tags,
        created_by: created_by
      )
      MCP::Tool::Response.new([{ type: "text", text: record.as_full_record.to_json }])
    rescue ActiveRecord::RecordInvalid => e
      raise MCP::Tool::Error, "Validation failed: #{e.message}"
    end
  end
end
