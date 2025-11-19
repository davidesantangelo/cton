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

  def dump(payload, *args)
    io = nil
    options = {}

    args.each do |arg|
      if arg.is_a?(Hash)
        options.merge!(arg)
      else
        io = arg
      end
    end

    io ||= options[:io]

    separator = options.fetch(:separator, "\n")
    pretty = options.fetch(:pretty, false)
    Encoder.new(separator: separator, pretty: pretty).encode(payload, io: io)
  end
  alias generate dump

  def load(cton_string, symbolize_names: false)
    Decoder.new(symbolize_names: symbolize_names).decode(cton_string)
  end
  alias parse load
end
