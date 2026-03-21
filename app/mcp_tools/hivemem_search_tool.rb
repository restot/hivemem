class HivememSearchTool < MCP::Tool
  description "Search knowledge records using BM25 full-text search with optional pre-filters. Returns ranked results with (shortlink, title, summary, tags, knowledge_type, project, score). Use without a query to browse/list records by filters."

  input_schema(
    properties: {
      query: { type: "string", description: "BM25 search query (terms are OR'd). Omit to browse/list by filters only." },
      project: { type: "string", description: "Filter by project name" },
      knowledge_type: { type: "string", description: "Filter by type: convention, pattern, decision, failure, reference, guide" },
      tags: { type: "array", items: { type: "string" }, description: "Filter by tags (AND logic)" },
      limit: { type: "integer", description: "Max results (default 20)" },
      offset: { type: "integer", description: "Offset for pagination (default 0)" }
    }
  )

  class << self
    def call(query: nil, project: nil, knowledge_type: nil, tags: nil, limit: 20, offset: 0, server_context: {})
      scope = KnowledgeRecord
        .filter_by_project(project)
        .filter_by_knowledge_type(knowledge_type)
        .filter_by_tags(tags)

      if query.present?
        begin
          scope = scope.bm25_search(query)
        rescue PG::Error, ActiveRecord::StatementInvalid => e
          return MCP::Tool::Response.new([{ type: "text", text: { error: "BM25 search failed: #{e.message}" }.to_json }], is_error: true)
        end
      else
        scope = scope.browse
      end

      total = scope.count(:all)
      records = scope.limit(limit).offset(offset)
      results = records.map(&:as_search_result)

      payload = {
        results: results,
        total: total,
        limit: limit,
        offset: offset,
        has_more: (offset + limit) < total
      }

      MCP::Tool::Response.new([{ type: "text", text: payload.to_json }])
    end
  end
end
