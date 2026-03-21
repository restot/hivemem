class HivememUpdateTool < MCP::Tool
  description "Update a knowledge record by shortlink. Can update any mutable field including tags (add/remove)."

  input_schema(
    properties: {
      shortlink: { type: "string", description: "Record shortlink" },
      title: { type: "string", description: "New title" },
      summary: { type: "string", description: "New summary" },
      content: { type: "string", description: "New content" },
      knowledge_type: { type: "string", description: "New knowledge type" },
      project: { type: "string", description: "New project" },
      tags: { type: "array", items: { type: "string" }, description: "Replace all tags with this array" },
      add_tags: { type: "array", items: { type: "string" }, description: "Tags to add (merged with existing)" },
      remove_tags: { type: "array", items: { type: "string" }, description: "Tags to remove" }
    },
    required: ["shortlink"]
  )

  class << self
    def call(shortlink:, title: nil, summary: nil, content: nil, knowledge_type: nil, project: nil, tags: nil, add_tags: nil, remove_tags: nil, server_context: {})
      record = KnowledgeRecord.find_by_shortlink!(shortlink)

      attrs = {}
      attrs[:title] = title if title
      attrs[:summary] = summary if summary
      attrs[:content] = content if content
      attrs[:knowledge_type] = knowledge_type if knowledge_type
      attrs[:project] = project if project

      if tags
        attrs[:tags] = tags
      else
        current_tags = record.tags.dup
        current_tags = (current_tags + Array(add_tags)).uniq if add_tags
        current_tags -= Array(remove_tags) if remove_tags
        attrs[:tags] = current_tags if add_tags || remove_tags
      end

      record.update!(attrs) if attrs.any?
      MCP::Tool::Response.new([{ type: "text", text: record.reload.as_full_record.to_json }])
    rescue ActiveRecord::RecordNotFound
      raise MCP::Tool::Error, "Record not found: #{shortlink}"
    rescue ActiveRecord::RecordInvalid => e
      raise MCP::Tool::Error, "Validation failed: #{e.message}"
    end
  end
end
