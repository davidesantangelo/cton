# frozen_string_literal: true

require "bigdecimal"
require_relative "cton/version"
require_relative "cton/encoder"
require_relative "cton/decoder"

module Cton
  class Error < StandardError; end
  class EncodeError < Error; end
  class ParseError < Error; end

  module_function

  def dump(payload, options = {})
    separator = options.fetch(:separator, "\n")
    Encoder.new(separator: separator).encode(payload)
  end
  alias generate dump

  def load(cton_string, symbolize_names: false)
    Decoder.new(symbolize_names: symbolize_names).decode(cton_string)
  end
  alias parse load
end

