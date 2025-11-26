# frozen_string_literal: true

module Cton
  # Result object for validation operations
  class ValidationResult
    attr_reader :errors

    def initialize(errors = [])
      @errors = errors.freeze
    end

    def valid?
      errors.empty?
    end

    def to_s
      return "Valid CTON" if valid?

      messages = errors.map(&:to_s)
      "Invalid CTON:\n  #{messages.join("\n  ")}"
    end
  end

  # Represents a single validation error with location info
  class ValidationError
    attr_reader :message, :line, :column, :source_excerpt

    def initialize(message:, line:, column:, source_excerpt: nil)
      @message = message
      @line = line
      @column = column
      @source_excerpt = source_excerpt
    end

    def to_s
      loc = "line #{line}, column #{column}"
      excerpt_str = source_excerpt ? " near '#{source_excerpt}'" : ""
      "#{message} at #{loc}#{excerpt_str}"
    end

    def to_h
      {
        message: message,
        line: line,
        column: column,
        source_excerpt: source_excerpt
      }
    end
  end

  # Lightweight validator that checks syntax without building full AST
  class Validator
    def initialize
      @errors = []
    end

    def validate(cton_string)
      @errors = []
      @raw_string = cton_string.to_s
      @pos = 0
      @length = @raw_string.length

      begin
        validate_document
        check_trailing_content
      rescue StopIteration
        # Validation complete
      end

      ValidationResult.new(@errors)
    end

    private

    def validate_document
      skip_ws_and_comments
      return if eos?

      if key_ahead?
        validate_key_value_pairs
      else
        validate_value
      end
    end

    def validate_key_value_pairs
      loop do
        skip_ws_and_comments
        break if eos?

        validate_key
        validate_value_for_key
        skip_ws_and_comments
      end
    end

    def validate_key
      skip_ws_and_comments
      start = @pos
      return if scan_key

      add_error("Invalid key", start)
      skip_to_recovery_point
    end

    def validate_value_for_key
      skip_ws_and_comments

      case peek
      when "("
        advance
        validate_object_contents
      when "["
        advance
        validate_array_contents
      when "="
        advance
        skip_ws_and_comments
        # After = we can have an object, array, or scalar
        if peek == "("
          advance
          validate_object_contents
        elsif peek == "["
          advance
          validate_array_contents
        else
          validate_scalar(allow_boundary: true)
        end
      else
        add_error("Expected '(', '[', or '=' after key", @pos)
        skip_to_recovery_point
      end
    end

    def validate_object_contents
      skip_ws_and_comments
      return if consume(")")

      loop do
        if eos?
          add_error("Unclosed object - expected ')'", @pos)
          return
        end

        validate_key
        unless consume("=")
          add_error("Expected '=' in object", @pos)
          skip_to_recovery_point
          return
        end
        validate_value

        skip_ws_and_comments

        if eos?
          add_error("Unclosed object - expected ')'", @pos)
          return
        end

        break if consume(")")

        unless consume(",")
          add_error("Expected ',' or ')' in object", @pos)
          skip_to_recovery_point
          return
        end
        skip_ws_and_comments
      end
    end

    def validate_array_contents
      length_start = @pos
      length = scan_integer
      if length.nil?
        add_error("Expected array length", length_start)
        skip_to_recovery_point
        return
      end

      unless consume("]")
        add_error("Expected ']' after array length", @pos)
        skip_to_recovery_point
        return
      end

      skip_ws_and_comments

      # Check for table header
      has_header = peek == "{"
      if has_header
        advance
        validate_header
      end

      unless consume("=")
        add_error("Expected '=' after array declaration", @pos)
        skip_to_recovery_point
        return
      end

      return if length.zero?

      if has_header
        validate_table_rows(length)
      else
        validate_array_elements(length)
      end
    end

    def validate_header
      loop do
        validate_key
        skip_ws_and_comments
        break if consume("}")

        next if consume(",")

        add_error("Expected ',' or '}' in header", @pos)
        skip_to_recovery_point
        return
      end
    end

    def validate_table_rows(length)
      length.times do |i|
        validate_scalar(allow_boundary: i == length - 1)
        # Table cells are separated by commas, rows by semicolons
        skip_ws_and_comments
        next unless i < length - 1

        unless consume(";") || peek == "," || eos?
          # More permissive - allow continued parsing
        end
      end
    end

    def validate_array_elements(length)
      length.times do |i|
        validate_value(allow_boundary: i == length - 1)
        skip_ws_and_comments
        if i < length - 1
          consume(",") # Optional comma handling
        end
      end
    end

    def validate_value(allow_boundary: false)
      skip_ws_and_comments

      case peek
      when "("
        advance
        validate_object_contents
      when "["
        advance
        validate_array_contents
      when '"'
        validate_string
      else
        validate_scalar(allow_boundary: allow_boundary)
      end
    end

    def validate_scalar(allow_boundary: false)
      skip_ws_and_comments
      return validate_string if peek == '"'

      start = @pos
      scan_until_terminator

      return unless @pos == start

      add_error("Empty value", start)
    end

    def validate_string
      start = @pos
      advance # consume opening quote

      loop do
        if eos?
          add_error("Unterminated string", start)
          return
        end

        char = current
        advance

        if char == "\\"
          if eos?
            add_error("Invalid escape sequence", @pos - 1)
            return
          end
          escaped = current
          advance
          unless ["n", "r", "t", '"', "\\"].include?(escaped)
            add_error("Unsupported escape sequence '\\#{escaped}'", @pos - 2)
          end
        elsif char == '"'
          return
        end
      end
    end

    def check_trailing_content
      skip_ws_and_comments
      return if eos?

      add_error("Unexpected trailing data", @pos)
    end

    # Helper methods

    def add_error(message, pos)
      line, col = calculate_location(pos)
      excerpt = extract_excerpt(pos)
      @errors << ValidationError.new(
        message: message,
        line: line,
        column: col,
        source_excerpt: excerpt
      )
    end

    def calculate_location(pos)
      consumed = @raw_string[0...pos]
      line = consumed.count("\n") + 1
      last_newline = consumed.rindex("\n")
      col = last_newline ? pos - last_newline : pos + 1
      [line, col]
    end

    def extract_excerpt(pos, length: 20)
      start = [pos - 5, 0].max
      finish = [pos + length, @length].min
      excerpt = @raw_string[start...finish]
      excerpt = "...#{excerpt}" if start.positive?
      excerpt = "#{excerpt}..." if finish < @length
      excerpt.gsub(/\s+/, " ")
    end

    def eos?
      @pos >= @length
    end

    def peek
      return nil if eos?

      @raw_string[@pos]
    end

    def current
      @raw_string[@pos]
    end

    def advance
      @pos += 1
    end

    def consume(char)
      if peek == char
        advance
        true
      else
        false
      end
    end

    def scan_key
      start = @pos
      @pos += 1 while @pos < @length && @raw_string[@pos].match?(/[0-9A-Za-z_.:-]/)
      @pos > start
    end

    def scan_integer
      start = @pos
      advance if peek == "-"
      @pos += 1 while @pos < @length && @raw_string[@pos].match?(/\d/)
      return nil if @pos == start || (@pos == start + 1 && @raw_string[start] == "-")

      @raw_string[start...@pos].to_i
    end

    def scan_until_terminator
      while @pos < @length
        char = @raw_string[@pos]
        break if [",", ";", ")", "]", "}"].include?(char) || char.match?(/\s/)

        @pos += 1
      end
    end

    def skip_ws_and_comments
      loop do
        @pos += 1 while @pos < @length && @raw_string[@pos].match?(/\s/)

        break unless @pos < @length && @raw_string[@pos] == "#"

        @pos += 1 while @pos < @length && @raw_string[@pos] != "\n"
      end
    end

    def skip_to_recovery_point
      while @pos < @length
        char = @raw_string[@pos]
        break if ["\n", ",", ";", ")", "]", "}"].include?(char)

        @pos += 1
      end
      advance if @pos < @length && [",", ";"].include?(@raw_string[@pos])
    end

    def key_ahead?
      saved_pos = @pos
      skip_ws_and_comments

      result = false
      if scan_key
        skip_ws_and_comments
        result = ["(", "[", "="].include?(peek)
      end

      @pos = saved_pos
      result
    end
  end
end
