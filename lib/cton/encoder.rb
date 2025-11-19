# frozen_string_literal: true

require "stringio"
require "time"
require "date"

module Cton
  class Encoder
    SAFE_TOKEN = /\A[0-9A-Za-z_.:-]+\z/
    NUMERIC_TOKEN = /\A-?(?:\d+)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/
    RESERVED_LITERALS = %w[true false null].freeze
    FLOAT_DECIMAL_PRECISION = Float::DIG

    def initialize(separator: "\n", pretty: false)
      @separator = separator || ""
      @pretty = pretty
      @indent_level = 0
    end

    def encode(payload, io: nil)
      @io = io || StringIO.new
      encode_root(payload)
      @io.string if @io.is_a?(StringIO)
    end

    private

    attr_reader :separator, :io, :pretty, :indent_level

    def encode_root(value)
      case value
      when Hash
        first = true
        value.each do |key, nested|
          io << separator unless first
          encode_top_level_pair(key, nested)
          first = false
        end
      else
        encode_value(value, context: :standalone)
      end
    end

    def encode_top_level_pair(key, value)
      io << format_key(key)
      encode_value(value, context: :top_pair)
    end

    def encode_value(value, context:)
      if defined?(Set) && value.is_a?(Set)
        value = value.to_a
      elsif defined?(OpenStruct) && value.is_a?(OpenStruct)
        value = value.to_h
      end

      case value
      when Hash
        encode_object(value)
      when Array
        encode_array(value)
      else
        io << "=" if context == :top_pair
        encode_scalar(value)
      end
    end

    def encode_object(hash)
      if hash.empty?
        io << "()"
        return
      end

      io << "("
      indent if pretty
      first = true
      hash.each do |key, value|
        if first
          first = false
        else
          io << ","
          newline if pretty
        end
        io << format_key(key) << "="
        encode_value(value, context: :object)
      end
      outdent if pretty
      io << ")"
    end

    def encode_array(list)
      length = list.length
      if length.zero?
        io << "[0]="
        return
      end

      io << "[" << length.to_s << "]"

      if table_candidate?(list)
        encode_table(list)
      else
        io << "="
        if list.all? { |value| scalar?(value) }
          encode_scalar_list(list)
        else
          encode_mixed_list(list)
        end
      end
    end

    def encode_table(rows)
      header = rows.first.keys
      io << "{"
      io << header.map { |key| format_key(key) }.join(",")
      io << "}="

      indent if pretty
      first_row = true
      rows.each do |row|
        if first_row
          first_row = false
        else
          io << ";"
          newline if pretty
        end

        first_col = true
        header.each do |field|
          io << "," unless first_col
          encode_scalar(row.fetch(field))
          first_col = false
        end
      end
      outdent if pretty
    end

    def encode_scalar_list(list)
      if pretty
        indent
        first = true
        list.each do |value|
          if first
            first = false
          else
            io << ","
            newline
          end
          encode_scalar(value)
        end
        outdent
      else
        first = true
        list.each do |value|
          io << "," unless first
          encode_scalar(value)
          first = false
        end
      end
    end

    def encode_mixed_list(list)
      indent if pretty
      first = true
      list.each do |value|
        if first
          first = false
        else
          io << ","
          newline if pretty
        end
        encode_value(value, context: :array)
      end
      outdent if pretty
    end

    def encode_scalar(value)
      case value
      when String
        encode_string(value)
      when TrueClass, FalseClass
        io << (value ? "true" : "false")
      when NilClass
        io << "null"
      when Numeric
        io << format_number(value)
      when Time, Date
        encode_string(value.iso8601)
      else
        raise EncodeError, "Unsupported value: #{value.class}"
      end
    end

    def encode_string(value)
      io << if value.empty?
              '""'
            elsif string_needs_quotes?(value)
              quote_string(value)
            else
              value
            end
    end

    def format_number(value)
      case value
      when Float
        return "null" if value.nan? || value.infinite?

        normalize_decimal_string(float_decimal_string(value))
      when Integer
        value.to_s
      else
        if defined?(BigDecimal) && value.is_a?(BigDecimal)
          normalize_decimal_string(value.to_s("F"))
        else
          value.to_s
        end
      end
    end

    def normalize_decimal_string(string)
      stripped = string.start_with?("+") ? string[1..] : string
      return "0" if zero_string?(stripped)

      if stripped.include?(".")
        stripped = stripped.sub(/0+\z/, "")
        stripped = stripped.sub(/\.\z/, "")
      end

      stripped
    end

    def zero_string?(string)
      string.match?(/\A-?0+(?:\.0+)?\z/)
    end

    def float_decimal_string(value)
      if defined?(BigDecimal)
        BigDecimal(value.to_s).to_s("F")
      else
        Kernel.format("%.#{FLOAT_DECIMAL_PRECISION}f", value)
      end
    end

    def format_key(key)
      key_string = key.to_s
      raise EncodeError, "Invalid key: #{key_string.inspect}" unless SAFE_TOKEN.match?(key_string)

      key_string
    end

    def string_needs_quotes?(value)
      return true unless SAFE_TOKEN.match?(value)

      RESERVED_LITERALS.include?(value) || numeric_like?(value)
    end

    def numeric_like?(value)
      NUMERIC_TOKEN.match?(value)
    end

    def quote_string(value)
      "\"#{escape_string(value)}\""
    end

    def escape_string(value)
      value.gsub(/["\\\n\r\t]/) do |char|
        case char
        when "\n" then "\\n"
        when "\r" then "\\r"
        when "\t" then "\\t"
        else
          "\\#{char}"
        end
      end
    end

    def scalar?(value)
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false || value.nil? || value.is_a?(Time) || value.is_a?(Date)
    end

    def table_candidate?(rows)
      return false if rows.empty?

      first = rows.first
      return false unless first.is_a?(Hash) && !first.empty?

      keys = first.keys
      rows.all? do |row|
        row.is_a?(Hash) && row.keys == keys && row.values.all? { |val| scalar?(val) }
      end
    end

    def indent
      @indent_level += 1
      newline
    end

    def outdent
      @indent_level -= 1
      newline
    end

    def newline
      io << "\n" << ("  " * indent_level)
    end
  end
end
