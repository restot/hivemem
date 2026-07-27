# Shared circuit breaker for optional inference services (embeddings, reranking,
# query expansion). All three are optional: when no endpoint is configured the
# service reports unavailable and callers degrade instead of attempting requests.
#
# Host classes must define URL_ENV_KEY and DEFAULT_URL.
module InferenceCircuit
  THRESHOLD = 3
  TIMEOUT = 60

  # True only when an endpoint is explicitly configured. Without this, an
  # unconfigured install would attempt (and fail) a request on every call
  # before the breaker trips, then retry every TIMEOUT seconds forever.
  def configured?
    ENV[self::URL_ENV_KEY].present?
  end

  def available?
    configured? && !circuit_open?
  end

  def circuit_open?
    circuit_mutex.synchronize do
      return false if @failure_count.to_i < THRESHOLD

      if @circuit_opened_at && Time.now - @circuit_opened_at > TIMEOUT
        @failure_count = 0
        @circuit_opened_at = nil
        false
      else
        true
      end
    end
  end

  private

  def circuit_mutex
    @circuit_mutex ||= Mutex.new
  end

  def base_url
    ENV.fetch(self::URL_ENV_KEY, self::DEFAULT_URL)
  end

  def check_circuit_breaker!
    raise "#{name} unavailable (no endpoint configured)" unless configured?
    raise "#{name} unavailable (circuit open)" if circuit_open?
  end

  def record_success!
    circuit_mutex.synchronize do
      @failure_count = 0
      @circuit_opened_at = nil
    end
  end

  def record_failure!
    circuit_mutex.synchronize do
      @failure_count = @failure_count.to_i + 1
      @circuit_opened_at = Time.now if @failure_count >= THRESHOLD
    end
  end
end
