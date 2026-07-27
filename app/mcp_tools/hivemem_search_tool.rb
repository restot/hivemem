class HivememSearchTool < MCP::Tool
  description "Search knowledge records using BM25, vector, or hybrid search. Modes: 'search' (BM25, fast), 'vsearch' (vector/semantic), 'query' (hybrid BM25+vector+reranking, best quality). Returns ranked results with (shortlink, title, summary, tags, knowledge_type, project, score)."

  input_schema(
    properties: {
      query: { type: "string", description: "Search query. Omit to browse/list by filters only." },
      mode: { type: "string", description: "Search mode: search (BM25), vsearch (vector), query (hybrid+reranking). Default: search", enum: %w[search vsearch query] },
      project: { type: "string", description: "Filter by project name" },
      knowledge_type: { type: "string", description: "Filter by type: convention, pattern, decision, failure, reference, guide, conversation" },
      tags: { type: "array", items: { type: "string" }, description: "Filter by tags (AND logic)" },
      classification: { type: "string", description: "Filter by classification: foundational, tactical, observational" },
      limit: { type: "integer", description: "Max results (default 20)" },
      offset: { type: "integer", description: "Offset for pagination (default 0)" }
    }
  )

  class << self
    def call(query: nil, mode: "search", project: nil, knowledge_type: nil, classification: nil, tags: nil, limit: 20, offset: 0, server_context: {})
      scope = KnowledgeRecord
        .filter_by_project(project)
        .filter_by_knowledge_type(knowledge_type)
        .filter_by_classification(classification)
        .filter_by_tags(tags)

      unless query.present?
        total = scope.count(:all)
        records = scope.browse.limit(limit).offset(offset)
        return respond(records.map(&:as_search_result), total, limit, offset)
      end

      begin
        result = HybridSearch.call(query: query, mode: mode, scope: scope, limit: limit, offset: offset)
        payload = {
          results: result[:results],
          total: result[:total],
          limit: limit,
          offset: offset,
          has_more: (offset + limit) < result[:total],
          mode: result[:mode]
        }
        MCP::Tool::Response.new([{ type: "text", text: payload.to_json }])
      rescue PG::Error, ActiveRecord::StatementInvalid => e
        MCP::Tool::Response.new([{ type: "text", text: { error: "Search failed: #{e.message}" }.to_json }], is_error: true)
      end
    end

    private

    def respond(results, total, limit, offset)
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
