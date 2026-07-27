class EmbeddingChunker
  MAX_CHUNK_CHARS = 6000 # ~2048 tokens, conservative estimate at 3 chars/token

  class << self
    def chunk(record)
      if record.knowledge_type == "conversation"
        chunk_conversation(record)
      else
        chunk_curated(record)
      end
    end

    private

    # Curated records: single chunk from title + summary + content
    def chunk_curated(record)
      text = [record.title, record.summary, record.content].compact.join("\n")
      [truncate(text)]
    end

    # Conversations: split by turn boundaries
    # Each turn (user prompt + agent response) becomes its own chunk
    def chunk_conversation(record)
      turns = split_into_turns(record.content)
      return chunk_curated(record) if turns.length <= 1

      turns.map { |turn| truncate(turn) }
    end

    def split_into_turns(content)
      # Turns are delimited by "User:" at the start of a line
      parts = content.split(/^(?=User:)/m)
      parts.reject(&:blank?).map(&:strip)
    end

    def truncate(text)
      return text if text.length <= MAX_CHUNK_CHARS

      # Truncate at paragraph boundary if possible
      truncated = text[0...MAX_CHUNK_CHARS]
      last_para = truncated.rindex("\n\n")
      last_para && last_para > MAX_CHUNK_CHARS * 0.5 ? truncated[0..last_para].strip : truncated.strip
    end
  end
end
