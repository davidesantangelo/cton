# frozen_string_literal: true

require "strscan"

module Cton
  class Decoder
    TERMINATORS = [",", ";", ")", "]", "}"].freeze

    def initialize(symbolize_names: false)
      @symbolize_names = symbolize_names
    end

    def decode(cton)
      @scanner = StringScanner.new(cton.to_s)
      skip_ws

      value = if key_ahead?
                parse_document
              else
                parse_value(allow_key_boundary: true)
              end

      skip_ws
      raise_error("Unexpected trailing data") unless @scanner.eos?

      value
    end

    private

    attr_reader :symbolize_names, :scanner

    def raise_error(message)
      line, col = calculate_location(@scanner.pos)
      raise ParseError, "#{message} at line #{line}, column #{col}"
    end

    def calculate_location(pos)
      string = @scanner.string
      consumed = string[0...pos]
      line = consumed.count("\n") + 1
      last_newline = consumed.rindex("\n")
      col = last_newline ? pos - last_newline : pos + 1
      [line, col]
    end

    def parse_document
      result = {}
      until @scanner.eos?
        key = parse_key_name
        value = parse_value_for_key
        result[key] = value
        skip_ws
      end
      result
    end

    def parse_value_for_key
      skip_ws
      if @scanner.scan("(")
        parse_object
      elsif @scanner.scan("[")
        parse_array
      elsif @scanner.scan("=")
        parse_scalar(allow_key_boundary: true)
      else
        raise_error("Unexpected token")
      end
    end

    def parse_object
      skip_ws
      return {} if @scanner.scan(")")

      pairs = {}
      loop do
        key = parse_key_name
        expect!("=")
        value = parse_value
        pairs[key] = value
        skip_ws
        break if @scanner.scan(")")

        expect!(",")
        skip_ws
      end
      pairs
    end

    def parse_array
      length = parse_integer_literal
      expect!("]")
      skip_ws

      header = parse_header if @scanner.peek(1) == "{"

      expect!("=")
      return [] if length.zero?

      header ? parse_table_rows(length, header) : parse_array_elements(length)
    end

    def parse_header
      expect!("{")
      fields = []
      loop do
        fields << parse_key_name
        break if @scanner.scan("}")

        expect!(",")
      end
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
      if @scanner.scan("(")
        parse_object
      elsif @scanner.scan("[")
        parse_array
      elsif @scanner.peek(1) == '"'
        parse_string
      else
        parse_scalar(allow_key_boundary: allow_key_boundary)
      end
    end

    def parse_scalar(allow_key_boundary: false)
      skip_ws
      return parse_string if @scanner.peek(1) == '"'

      @scanner.pos

      token = if allow_key_boundary
                scan_until_boundary_or_terminator
              else
                scan_until_terminator
              end

      raise_error("Empty value") if token.nil? || token.empty?

      convert_scalar(token)
    end

    def scan_until_terminator
      @scanner.scan(/[^,;\]\}\)\(\[\{\s]+/)
    end

    def scan_until_boundary_or_terminator
      start_pos = @scanner.pos

      chunk = @scanner.scan(/[0-9A-Za-z_.:-]+/)
      return nil unless chunk

      boundary_idx = find_key_boundary(start_pos)

      if boundary_idx
        length = boundary_idx - start_pos
        @scanner.pos = start_pos
        token = @scanner.peek(length)
        @scanner.pos += length
        token
      else
        @scanner.pos = start_pos + chunk.length
        chunk
      end
    end

    def find_key_boundary(from_index)
      str = @scanner.string
      len = str.length
      idx = from_index

      while idx < len
        char = str[idx]

        return nil if TERMINATORS.include?(char) || whitespace?(char) || "([{".include?(char)

        if safe_key_char?(char)
          key_end = idx
          key_end += 1 while key_end < len && safe_key_char?(str[key_end])

          next_char_idx = key_end

          if next_char_idx < len
            next_char = str[next_char_idx]
            return idx if ["(", "[", "="].include?(next_char) && (idx > from_index)
          end
        end

        idx += 1
      end
      nil
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
      loop do
        raise_error("Unterminated string") if @scanner.eos?

        char = @scanner.getch

        if char == "\\"
          escaped = @scanner.getch
          raise_error("Invalid escape sequence") if escaped.nil?
          buffer << case escaped
                    when "n" then "\n"
                    when "r" then "\r"
                    when "t" then "\t"
                    when '"', "\\" then escaped
                    else
                      raise_error("Unsupported escape sequence")
                    end
        elsif char == '"'
          break
        else
          buffer << char
        end
      end
      buffer
    end

    def parse_key_name
      skip_ws
      token = @scanner.scan(/[0-9A-Za-z_.:-]+/)
      raise_error("Invalid key") if token.nil?
      symbolize_names ? token.to_sym : token
    end

    def parse_integer_literal
      token = @scanner.scan(/-?\d+/)
      raise_error("Expected digits") if token.nil?
      Integer(token, 10)
    rescue ArgumentError
      raise_error("Invalid length literal")
    end

    def symbolize_keys(row)
      symbolize_names ? row.transform_keys(&:to_sym) : row
    end

    def expect!(char)
      skip_ws
      return if @scanner.scan(Regexp.new(Regexp.escape(char)))

      raise_error("Expected #{char.inspect}, got #{@scanner.peek(1).inspect}")
    end

    def skip_ws
      @scanner.skip(/\s+/)
    end

    def whitespace?(char)
      [" ", "\t", "\n", "\r"].include?(char)
    end

    def key_ahead?
      pos = @scanner.pos
      skip_ws

      if @scanner.scan(/[0-9A-Za-z_.:-]+/)
        skip_ws
        next_char = @scanner.peek(1)
        result = ["(", "[", "="].include?(next_char)
        @scanner.pos = pos
        result
      else
        @scanner.pos = pos
        false
      end
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
  end
end
