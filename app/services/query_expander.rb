require "net/http"
require "json"

class QueryExpander
  URL_ENV_KEY = "EXPANDER_URL".freeze
  DEFAULT_URL = "http://model-runner.docker.internal:12434/engines/v1".freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a search query expander. Given a search query, generate 3-5 alternative phrasings that capture the same intent using different terminology.

    Rules:
    - Each variant should use different words than the original
    - Include both technical and colloquial phrasings
    - Keep each variant under 10 words
    - Return one variant per line, nothing else
    - No numbering, no bullets, no preamble
  PROMPT

  class << self
    include InferenceCircuit

    def expand(query)
      check_circuit_breaker!

      uri = URI(endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = {
        model: model_name,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: query }
        ],
        max_tokens: 200,
        temperature: 0.7
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "Query expansion failed: #{response.code} #{response.body}"
      end

      result = JSON.parse(response.body)
      text = result.dig("choices", 0, "message", "content") || ""
      variants = text.strip.split("\n").map(&:strip).reject(&:empty?).first(5)

      record_success!
      variants
    rescue StandardError => e
      record_failure!
      raise
    end

    private

    def endpoint
      base_url + "/chat/completions"
    end

    def model_name
      ENV.fetch("EXPANDER_MODEL", "ai/qwen3")
    end
  end
end
