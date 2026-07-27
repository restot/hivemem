Rails.application.config.after_initialize do
  next unless ENV["EMBEDDINGS_URL"].present?

  Thread.new do
    sleep 2
    EmbeddingClient.embed("warmup")
    Rails.logger.info("Embedding model warmed up")
  rescue => e
    Rails.logger.warn("Embedding warmup failed: #{e.message}")
  end
end
