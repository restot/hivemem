class RecordEmbedding < ApplicationRecord
  belongs_to :knowledge_record

  validates :embedding, presence: true
  validates :chunk_index, presence: true
  validates :chunk_text, presence: true
  validates :model_id, presence: true

  scope :current_model, -> { where(model_id: EmbeddingClient.current_model_id) }
  scope :stale_model, -> { where.not(model_id: EmbeddingClient.current_model_id) }

  scope :nearest_to, ->(query_embedding, limit: 20) {
    current_model
      .select("record_embeddings.*, 1 - (embedding <=> '#{query_embedding}') AS vector_score")
      .order(Arel.sql("embedding <=> '#{query_embedding}'"))
      .limit(limit)
  }
end
