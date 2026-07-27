require "net/http"
require "json"

class RerankerClient
  URL_ENV_KEY = "RERANKER_URL".freeze
  DEFAULT_URL = "http://model-runner.docker.internal:12434/engines/v1".freeze

  SYSTEM_PROMPT = "Judge whether the document is relevant to the query. Reply with only 'yes' or 'no'.".freeze

  class << self
    include InferenceCircuit

    # Score a batch of documents against a query
    # Returns array of {index:, score:} sorted by score desc
    def rerank(query, documents)
      check_circuit_breaker!

      scored = documents.each_with_index.map do |doc, i|
        score = score_pair(query, doc)
        { index: i, score: score }
      end

      record_success!
      scored.sort_by { |s| -s[:score] }
    rescue StandardError => e
      record_failure!
      raise
    end

    private

    # Score a single query-document pair using generative reranking
    # Extracts probability of "yes" from logprobs
    def score_pair(query, document)
      uri = URI(endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = {
        model: model_name,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: "Query: #{query}\nDocument: #{document}" }
        ],
        max_tokens: 1,
        logprobs: true,
        top_logprobs: 5,
        temperature: 0
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "Reranker request failed: #{response.code} #{response.body}"
      end

      result = JSON.parse(response.body)
      extract_yes_probability(result)
    end

    def extract_yes_probability(result)
      logprobs = result.dig("choices", 0, "logprobs", "content", 0, "top_logprobs")
      return 0.5 unless logprobs

      yes_entry = logprobs.find { |lp| lp["token"].strip.downcase.start_with?("yes") }
      no_entry = logprobs.find { |lp| lp["token"].strip.downcase.start_with?("no") }

      yes_logprob = yes_entry ? yes_entry["logprob"] : -10
      no_logprob = no_entry ? no_entry["logprob"] : -10

      yes_prob = Math.exp(yes_logprob)
      no_prob = Math.exp(no_logprob)

      total = yes_prob + no_prob
      total > 0 ? yes_prob / total : 0.5
    end

    def endpoint
      base_url + "/chat/completions"
    end

    def model_name
      ENV.fetch("RERANKER_MODEL", "ai/qwen3-reranker")
    end
  end
end
