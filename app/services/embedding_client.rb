require "net/http"
require "json"

class EmbeddingClient
  MODEL_ID = ENV.fetch("EMBEDDING_MODEL_ID", "embeddinggemma-300m-v1")
  URL_ENV_KEY = "EMBEDDINGS_URL".freeze
  DEFAULT_URL = "http://model-runner.docker.internal:12434/engines/v1".freeze

  class << self
    include InferenceCircuit

    def current_model_id
      MODEL_ID
    end

    def embed(text)
      check_circuit_breaker!

      uri = URI(endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { model: model_name, input: text }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "Embedding request failed: #{response.code} #{response.body}"
      end

      result = JSON.parse(response.body)
      record_success!
      result.dig("data", 0, "embedding")
    rescue StandardError => e
      record_failure!
      raise
    end

    def batch_embed(texts)
      check_circuit_breaker!

      uri = URI(endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { model: model_name, input: texts }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 120) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "Batch embedding request failed: #{response.code} #{response.body}"
      end

      result = JSON.parse(response.body)
      record_success!
      result["data"].sort_by { |d| d["index"] }.map { |d| d["embedding"] }
    rescue StandardError => e
      record_failure!
      raise
    end

    private

    def endpoint
      base_url + "/embeddings"
    end

    def model_name
      ENV.fetch("EMBEDDINGS_MODEL", "ai/embeddinggemma")
    end
  end
end
