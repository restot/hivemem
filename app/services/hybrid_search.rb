class HybridSearch
  RRF_K = 60
  RERANK_CANDIDATES = 30

  class << self
    # mode: :search (BM25), :vsearch (vector), :query (hybrid+reranking)
    def call(query:, mode: :search, scope: KnowledgeRecord.all, limit: 20, offset: 0)
      case mode.to_sym
      when :search
        bm25_search(query, scope, limit, offset)
      when :vsearch
        vector_search(query, scope, limit, offset)
      when :query
        hybrid_search(query, scope, limit, offset)
      else
        raise ArgumentError, "Unknown search mode: #{mode}"
      end
    end

    private

    # --- Tier 1: BM25 only ---
    def bm25_search(query, scope, limit, offset)
      results = scope.bm25_search(query)
      total = results.count(:all)
      records = results.limit(limit).offset(offset)
      { results: records.map(&:as_search_result), total: total, mode: :search }
    end

    # --- Tier 2: Vector only ---
    def vector_search(query, scope, limit, offset)
      unless EmbeddingClient.available?
        raise "Vector search unavailable: no embedding endpoint configured (set EMBEDDINGS_URL)"
      end

      query_embedding = EmbeddingClient.embed(query)
      embedding_vector = "[#{query_embedding.join(',')}]"

      record_ids_with_scores = RecordEmbedding
        .current_model
        .joins(:knowledge_record)
        .merge(scope)
        .nearest_to(embedding_vector, limit: limit + offset)
        .group_by(&:knowledge_record_id)
        .transform_values { |chunks| chunks.max_by { |c| c.vector_score.to_f } }

      record_ids = record_ids_with_scores.keys
      records = KnowledgeRecord.where(id: record_ids)
      scores = record_ids_with_scores.transform_values { |c| c.vector_score.to_f }

      sorted = records.sort_by { |r| -(scores[r.id] || 0) }
      paged = sorted.drop(offset).first(limit)

      results = paged.map do |r|
        result = r.as_search_result
        result[:score] = scores[r.id]
        result
      end

      { results: results, total: record_ids.length, mode: :vsearch }
    end

    # --- Tier 3: Hybrid (BM25 + vector + expansion + reranking) ---
    def hybrid_search(query, scope, limit, offset)
      # Stages that did not run. Reported to the caller so a BM25-only result
      # set is never mistaken for a full hybrid one.
      degraded = []

      # Step 1: Query expansion
      queries = [query]
      if QueryExpander.available?
        begin
          expanded = QueryExpander.expand(query)
          queries += expanded
        rescue StandardError => e
          Rails.logger.warn("Query expansion failed, continuing with original: #{e.message}")
          degraded << :expansion
        end
      else
        degraded << :expansion
      end

      # Step 2: BM25 search (all query variants)
      bm25_ranked = {}
      queries.each_with_index do |q, qi|
        weight = qi == 0 ? 2 : 1 # original query counted twice
        begin
          results = scope.bm25_search(q).limit(RERANK_CANDIDATES)
          results.each_with_index do |record, rank|
            bm25_ranked[record.id] ||= { record: record, rrf_score: 0.0 }
            bm25_ranked[record.id][:rrf_score] += weight * (1.0 / (RRF_K + rank + 1))
          end
        rescue PG::Error, ActiveRecord::StatementInvalid => e
          Rails.logger.warn("BM25 search failed for '#{q}': #{e.message}")
        end
      end

      # Step 3: Vector search (all query variants)
      if EmbeddingClient.available?
        vector_hits = 0
        queries.each_with_index do |q, qi|
          weight = qi == 0 ? 2 : 1
          begin
            query_embedding = EmbeddingClient.embed(q)
            embedding_vector = "[#{query_embedding.join(',')}]"

            chunks = RecordEmbedding
              .current_model
              .joins(:knowledge_record)
              .merge(scope)
              .nearest_to(embedding_vector, limit: RERANK_CANDIDATES)

            seen_records = Set.new
            chunks.each_with_index do |chunk, rank|
              rid = chunk.knowledge_record_id
              next if seen_records.include?(rid)
              seen_records << rid

              unless bm25_ranked[rid]
                # Must go through scope: a bare KnowledgeRecord.find would
                # bypass the project/tag/classification filters applied above.
                record = scope.find_by(id: rid)
                next unless record

                bm25_ranked[rid] = { record: record, rrf_score: 0.0 }
              end
              bm25_ranked[rid][:rrf_score] += weight * (1.0 / (RRF_K + rank + 1))
            end
            vector_hits += 1
          rescue StandardError => e
            Rails.logger.warn("Vector search failed for '#{q}': #{e.message}")
          end
        end
        degraded << :vector if vector_hits.zero?
      else
        degraded << :vector
      end

      # Step 4: Sort by RRF score
      candidates = bm25_ranked.values.sort_by { |c| -c[:rrf_score] }.first(RERANK_CANDIDATES)

      # Step 5: Reranking
      if RerankerClient.available? && candidates.any?
        begin
          doc_texts = candidates.map { |c| c[:record].content.to_s.truncate(2000) }
          reranked = RerankerClient.rerank(query, doc_texts)

          reranked_candidates = reranked.map do |r|
            candidates[r[:index]].merge(score: r[:score])
          end
          candidates = reranked_candidates
        rescue StandardError => e
          Rails.logger.warn("Reranking failed, using RRF scores: #{e.message}")
          candidates.each { |c| c[:score] = c[:rrf_score] }
          degraded << :rerank
        end
      else
        candidates.each { |c| c[:score] = c[:rrf_score] }
        degraded << :rerank if candidates.any?
      end

      # Paginate
      paged = candidates.drop(offset).first(limit)
      results = paged.map do |c|
        result = c[:record].as_search_result
        result[:score] = c[:score]
        result
      end

      response = { results: results, total: candidates.length, mode: :query }
      response[:degraded] = degraded if degraded.any?
      response
    end
  end
end
