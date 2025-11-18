# frozen_string_literal: true

require "bigdecimal"
require_relative "cton/version"

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

  class Encoder
    SAFE_TOKEN = /\A[0-9A-Za-z_.:-]+\z/.freeze
    NUMERIC_TOKEN = /\A-?(?:\d+)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/.freeze
    RESERVED_LITERALS = %w[true false null].freeze

    def initialize(separator: "\n")
      @separator = separator || ""
    end

    def encode(payload)
      encode_root(payload)
    end

    private

    attr_reader :separator

    def encode_root(value)
      case value
      when Hash
        value.map { |key, nested| encode_top_level_pair(key, nested) }.join(separator)
      else
        encode_value(value, context: :standalone)
      end
    end

    def encode_top_level_pair(key, value)
      "#{format_key(key)}#{encode_value(value, context: :top_pair)}"
    end

    def encode_value(value, context:)
      case value
      when Hash
        encode_object(value)
      when Array
        encode_array(value)
      else
        prefix = context == :top_pair ? "=" : ""
        "#{prefix}#{encode_scalar(value)}"
      end
    end

    def encode_object(hash)
      return "()" if hash.empty?

      pairs = hash.map do |key, value|
        "#{format_key(key)}=#{encode_value(value, context: :object)}"
      end
      "(#{pairs.join(',')})"
    end

    def encode_array(list)
      length = list.length
      return "[0]=" if length.zero?

      if table_candidate?(list)
        "[#{length}]#{encode_table(list)}"
      else
        body = if list.all? { |value| scalar?(value) }
                 list.map { |value| encode_scalar(value) }.join(",")
               else
                 list.map { |value| encode_array_element(value) }.join(",")
               end
        "[#{length}]=#{body}"
      end
    end

    def encode_table(rows)
      header = rows.first.keys
      header_token = "{#{header.map { |key| format_key(key) }.join(',')}}"
      table_rows = rows.map do |row|
        header.map { |field| encode_scalar(row.fetch(field)) }.join(",")
      end
      "#{header_token}=#{table_rows.join(';')}"
    end

    def encode_array_element(value)
      encode_value(value, context: :array)
    end

    def encode_scalar(value)
      case value
      when String
        encode_string(value)
      when TrueClass, FalseClass
        value ? "true" : "false"
      when NilClass
        "null"
      when Numeric
        format_number(value)
      else
        raise EncodeError, "Unsupported value: #{value.class}"
      end
    end

    def encode_string(value)
      return '""' if value.empty?

      string_needs_quotes?(value) ? quote_string(value) : value
    end

    FLOAT_DECIMAL_PRECISION = Float::DIG

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
      stripped = string.start_with?("+") ? string[1..-1] : string
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
      unless SAFE_TOKEN.match?(key_string)
        raise EncodeError, "Invalid key: #{key_string.inspect}"
      end
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
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false || value.nil?
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
  end

  class Decoder
    TERMINATORS = [",", ";", ")", "]", "}"].freeze

    def initialize(symbolize_names: false)
      @symbolize_names = symbolize_names
    end

    def decode(cton)
      @source = cton.to_s
      @index = 0
      skip_ws

      value = if key_ahead?(@index)
                parse_document
              else
                parse_value(allow_key_boundary: true)
              end

      skip_ws
      raise ParseError, "Unexpected trailing data" unless eof?

      value
    end

    private

    attr_reader :symbolize_names

    def parse_document
      result = {}
      until eof?
        key = parse_key_name
        value = parse_value_for_key
        assign_pair(result, key, value)
        skip_ws
      end
      result
    end

    def parse_value_for_key
      skip_ws
      char = current_char
      case char
      when "("
        parse_object
      when "["
        parse_array
      when "="
        advance
        parse_scalar(allow_key_boundary: true)
      else
        raise ParseError, "Unexpected token #{char.inspect} while reading value"
      end
    end

    def parse_object
      expect!("(")
      skip_ws
      if current_char == ")"
        expect!(")")
        return {}
      end

      pairs = {}
      loop do
        key = parse_key_name
        expect!("=")
        value = parse_value
        assign_pair(pairs, key, value)
        skip_ws
        break if current_char == ")"
        expect!(",")
        skip_ws
      end
      expect!(")")
      pairs
    end

    def parse_array
      expect!("[")
      length = parse_integer_literal
      expect!("]")
      skip_ws

      header = parse_header if current_char == "{"

      expect!("=")
      return [] if length.zero?

      header ? parse_table_rows(length, header) : parse_array_elements(length)
    end

    def parse_header
      expect!("{")
      fields = []
      loop do
        fields << parse_key_name
        break if current_char == "}"
        expect!(",")
      end
      expect!("}")
      fields
    end

    def parse_table_rows(length, header)
      rows = []
      length.times do |row_index|
        row = {}
        header.each_with_index do |field, column_index|
          allow_boundary = row_index == length - 1 && column_index == header.length - 1
          row[field] = parse_scalar(allow_key_boundary: allow_boundary)
          expect!(",") if column_index < header.length - 1
        end
        rows << symbolize_keys(row)
        expect!(";") if row_index < length - 1
      end
      rows
    end

    def parse_array_elements(length)
      values = []
      length.times do |index|
        allow_boundary = index == length - 1
        values << parse_value(allow_key_boundary: allow_boundary)
        expect!(",") if index < length - 1
      end
      values
    end

    def parse_value(allow_key_boundary: false)
      skip_ws
      char = current_char
      raise ParseError, "Unexpected end of input" if char.nil?

      case char
      when "("
        parse_object
      when "["
        parse_array
      when '"'
        parse_string
      else
        parse_scalar(allow_key_boundary: allow_key_boundary)
      end
    end

    def parse_scalar(terminators: TERMINATORS, allow_key_boundary: false)
      skip_ws
      return parse_string if current_char == '"'

      start = @index
      limit_index = allow_key_boundary ? next_key_index(@index) : nil
      exit_reason = nil

      while !eof?
        if limit_index && @index >= limit_index
          exit_reason = :boundary
          break
        end

        char = current_char

        if char.nil?
          exit_reason = :eof
          break
        elsif terminators.include?(char)
          exit_reason = :terminator
          break
        elsif whitespace?(char)
          exit_reason = :whitespace
          break
        elsif "()[]{}".include?(char)
          exit_reason = :structure
          break
        end

        @index += 1
      end

      token = if exit_reason == :boundary && limit_index
                @source[start...limit_index]
              else
                @source[start...@index]
              end

      raise ParseError, "Empty value" if token.nil? || token.empty?

      convert_scalar(token)
    end

    def convert_scalar(token)
      case token
      when "true" then true
      when "false" then false
      when "null" then nil
      else
        if integer?(token)
          token.to_i
        elsif float?(token)
          token.to_f
        else
          token
        end
      end
    end

    def parse_string
      expect!("\"")
      buffer = +""
      while !eof?
        char = current_char
        raise ParseError, "Unterminated string" if char.nil?

        if char == '\\'
          @index += 1
          escaped = current_char
          raise ParseError, "Invalid escape sequence" if escaped.nil?
          buffer << case escaped
                    when 'n' then "\n"
                    when 'r' then "\r"
                    when 't' then "\t"
                    when '"', '\\' then escaped
                    else
                      raise ParseError, "Unsupported escape sequence"
                    end
        elsif char == '"'
          break
        else
          buffer << char
        end
        @index += 1
      end
      expect!("\"")
      buffer
    end

    def parse_key_name
      skip_ws
      start = @index
      while !eof? && safe_key_char?(current_char)
        @index += 1
      end
      token = @source[start...@index]
      raise ParseError, "Invalid key" if token.nil? || token.empty?
      symbolize_names ? token.to_sym : token
    end

    def parse_integer_literal
      start = @index
      while !eof? && current_char =~ /\d/
        @index += 1
      end
      token = @source[start...@index]
      raise ParseError, "Expected digits" if token.nil? || token.empty?
      Integer(token, 10)
    rescue ArgumentError
      raise ParseError, "Invalid length literal"
    end

    def assign_pair(hash, key, value)
      hash[key] = value
    end

    def symbolize_keys(row)
      symbolize_names ? row.transform_keys(&:to_sym) : row
    end

    def expect!(char)
      skip_ws
      actual = current_char
      raise ParseError, "Expected #{char.inspect}, got #{actual.inspect}" unless actual == char
      @index += 1
    end

    def skip_ws
      @index += 1 while !eof? && whitespace?(current_char)
    end

    def whitespace?(char)
      char == " " || char == "\t" || char == "\n" || char == "\r"
    end

    def eof?
      @index >= @source.length
    end

    def current_char
      @source[@index]
    end

    def advance
      @index += 1
    end

    def key_ahead?(offset)
      idx = offset
      idx += 1 while idx < @source.length && whitespace?(@source[idx])
      start = idx
      while idx < @source.length && safe_key_char?(@source[idx])
        idx += 1
      end
      return false if idx == start
      next_char = @source[idx]
      ["(", "[", "="].include?(next_char)
    end

    def safe_key_char?(char)
      !char.nil? && char.match?(/[0-9A-Za-z_.:-]/)
    end

    def integer?(token)
      token.match?(/\A-?(?:0|[1-9]\d*)\z/)
    end

    def float?(token)
      token.match?(/\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/)
    end

    def next_key_index(from_index)
      idx = from_index
      in_string = false

      while idx < @source.length
        char = @source[idx]

        if in_string
          if char == '\\'
            idx += 2
            next
          elsif char == '"'
            in_string = false
            idx += 1
            next
          else
            idx += 1
            next
          end
        else
          case char
          when '"'
            in_string = true
            idx += 1
            next
          else
            if safe_key_char?(char)
              start = idx
              idx += 1 while idx < @source.length && safe_key_char?(@source[idx])
              next_char = @source[idx]
              if start > from_index && ["(", "[", "="].include?(next_char)
                return start
              end
              idx = start + 1
              next
            end
            idx += 1
          end
        end
      end

      nil
    end
  end
end

