# frozen_string_literal: true

require "bigdecimal"
require_relative "cton/version"
require_relative "cton/encoder"
require_relative "cton/decoder"
require_relative "cton/validator"
require_relative "cton/stats"
require_relative "cton/type_registry"

module Cton
  class Error < StandardError; end
  class EncodeError < Error; end

  # Enhanced ParseError with structured location information
  class ParseError < Error
    attr_reader :line, :column, :source_excerpt, :suggestions

    def initialize(message, line: nil, column: nil, source_excerpt: nil, suggestions: nil)
      @line = line
      @column = column
      @source_excerpt = source_excerpt
      @suggestions = suggestions || []

      full_message = message
      full_message = "#{full_message} at line #{line}, column #{column}" if line && column
      full_message = "#{full_message} near '#{source_excerpt}'" if source_excerpt
      full_message = "#{full_message}. #{@suggestions.join(". ")}" unless @suggestions.empty?

      super(full_message)
    end

    def to_h
      {
        message: message,
        line: line,
        column: column,
        source_excerpt: source_excerpt,
        suggestions: suggestions
      }
    end
  end

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
    decimal_mode = options.fetch(:decimal_mode, :fast)
    comments = options.fetch(:comments, nil)
    Encoder.new(separator: separator, pretty: pretty, decimal_mode: decimal_mode, comments: comments).encode(payload,
                                                                                                             io: io)
  end
  alias generate dump

  def load(cton_string, symbolize_names: false)
    Decoder.new(symbolize_names: symbolize_names).decode(cton_string)
  end
  alias parse load

  # Validate a CTON string without parsing
  #
  # @param cton_string [String] The CTON string to validate
  # @return [ValidationResult] Result object with errors array
  #
  # @example
  #   result = Cton.validate("key=value")
  #   result.valid? # => true
  #
  #   result = Cton.validate("key=(broken")
  #   result.valid? # => false
  #   result.errors.first.message # => "Expected ')' in object"
  def validate(cton_string)
    Validator.new.validate(cton_string)
  end

  # Check if a CTON string is valid
  #
  # @param cton_string [String] The CTON string to check
  # @return [Boolean] true if valid, false otherwise
  #
  # @example
  #   Cton.valid?("key=value")  # => true
  #   Cton.valid?("key=(")      # => false
  def valid?(cton_string)
    validate(cton_string).valid?
  end

  # Get token statistics comparing CTON vs JSON
  #
  # @param data [Hash, Array] The data to analyze
  # @return [Stats] Statistics object with comparison data
  #
  # @example
  #   stats = Cton.stats({ name: "test", values: [1, 2, 3] })
  #   puts stats.savings_percent  # => 45.5
  #   puts stats.to_s
  def stats(data)
    Stats.new(data)
  end

  # Get statistics as a hash
  #
  # @param data [Hash, Array] The data to analyze
  # @return [Hash] Statistics hash
  def stats_hash(data)
    stats(data).to_h
  end
end
