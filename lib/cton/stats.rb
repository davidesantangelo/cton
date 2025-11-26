# frozen_string_literal: true

require "json"

module Cton
  # Token statistics for comparing JSON vs CTON efficiency
  class Stats
    # Rough estimate: GPT models average ~4 characters per token
    CHARS_PER_TOKEN = 4

    attr_reader :data, :json_string, :cton_string

    def initialize(data, cton_string: nil, json_string: nil)
      @data = data
      @json_string = json_string || JSON.generate(data)
      @cton_string = cton_string || Cton.dump(data)
    end

    def json_chars
      json_string.length
    end

    def cton_chars
      cton_string.length
    end

    def json_bytes
      json_string.bytesize
    end

    def cton_bytes
      cton_string.bytesize
    end

    def savings_chars
      json_chars - cton_chars
    end

    def savings_bytes
      json_bytes - cton_bytes
    end

    def savings_percent
      return 0.0 if json_chars.zero?

      ((1 - (cton_chars.to_f / json_chars)) * 100).round(1)
    end

    def estimated_json_tokens
      (json_chars / CHARS_PER_TOKEN.to_f).ceil
    end

    def estimated_cton_tokens
      (cton_chars / CHARS_PER_TOKEN.to_f).ceil
    end

    def estimated_token_savings
      estimated_json_tokens - estimated_cton_tokens
    end

    def to_h
      {
        json_chars: json_chars,
        cton_chars: cton_chars,
        json_bytes: json_bytes,
        cton_bytes: cton_bytes,
        savings_chars: savings_chars,
        savings_bytes: savings_bytes,
        savings_percent: savings_percent,
        estimated_tokens: {
          json: estimated_json_tokens,
          cton: estimated_cton_tokens,
          savings: estimated_token_savings
        }
      }
    end

    def to_s
      <<~STATS
        JSON:  #{json_chars} chars / #{json_bytes} bytes (~#{estimated_json_tokens} tokens)
        CTON:  #{cton_chars} chars / #{cton_bytes} bytes (~#{estimated_cton_tokens} tokens)
        Saved: #{savings_percent}% (#{savings_chars} chars, ~#{estimated_token_savings} tokens)
      STATS
    end

    # Compare multiple encoding options
    def self.compare(data, options: {})
      results = {}

      # Standard CTON
      results[:cton] = new(data).to_h

      # Inline CTON (no separators)
      inline_cton = Cton.dump(data, separator: "")
      results[:cton_inline] = {
        chars: inline_cton.length,
        bytes: inline_cton.bytesize
      }

      # Pretty CTON
      pretty_cton = Cton.dump(data, pretty: true)
      results[:cton_pretty] = {
        chars: pretty_cton.length,
        bytes: pretty_cton.bytesize
      }

      # JSON variants
      json = JSON.generate(data)
      results[:json] = {
        chars: json.length,
        bytes: json.bytesize
      }

      pretty_json = JSON.pretty_generate(data)
      results[:json_pretty] = {
        chars: pretty_json.length,
        bytes: pretty_json.bytesize
      }

      results
    end
  end
end
