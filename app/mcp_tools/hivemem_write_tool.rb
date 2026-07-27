class HivememWriteTool < MCP::Tool
  description "Create a new knowledge record. Returns the created record with generated shortlink."

  input_schema(
    properties: {
      title: { type: "string", description: "Short descriptive title" },
      content: { type: "string", description: "Full record content" },
      knowledge_type: { type: "string", description: "One of: convention, pattern, decision, failure, reference, guide, conversation" },
      project: { type: "string", description: "Project identifier (e.g. telegram-bot, hivemem)" },
      summary: { type: "string", description: "1-3 sentence summary for search results" },
      tags: { type: "array", items: { type: "string" }, description: "Free-form tags" },
      created_by: { type: "string", description: "Actor identifier" },
      classification: { type: "string", description: "foundational (permanent), tactical (default, medium-term), or observational (short-term)" },
      evidence: { type: "object", description: "Evidence links: {commit, date, issue, file, bead}" },
      relates_to: { type: "array", items: { type: "string" }, description: "Shortlinks of related records" },
      supersedes: { type: "array", items: { type: "string" }, description: "Shortlinks of records this replaces" },
      metadata: { type: "object", description: "Type-specific fields: resolution (failure), rationale (decision), files (pattern/reference)" }
    },
    required: %w[title content knowledge_type project]
  )

  class << self
    def call(title:, content:, knowledge_type:, project:, summary: nil, tags: [], created_by: nil, classification: nil, evidence: {}, relates_to: [], supersedes: [], metadata: {}, server_context: {})
      record = KnowledgeRecord.create!(
        title: title,
        content: content,
        knowledge_type: knowledge_type,
        project: project,
        summary: summary,
        tags: tags,
        created_by: created_by,
        classification: classification,
        evidence: evidence,
        relates_to: relates_to,
        supersedes: supersedes,
        metadata: metadata
      )
      MCP::Tool::Response.new([{ type: "text", text: record.as_full_record.to_json }])
    rescue ActiveRecord::RecordInvalid => e
      raise MCP::Tool::Error, "Validation failed: #{e.message}"
    end
  end
end
