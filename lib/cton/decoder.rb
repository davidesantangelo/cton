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
      raise ParseError, "Unexpected trailing data" unless @scanner.eos?

      value
    end

    private

    attr_reader :symbolize_names, :scanner

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
      if @scanner.scan(/\(/)
        parse_object
      elsif @scanner.scan(/\[/)
        parse_array
      elsif @scanner.scan(/=/)
        parse_scalar(allow_key_boundary: true)
      else
        raise ParseError, "Unexpected token at position #{@scanner.pos}"
      end
    end

    def parse_object
      skip_ws
      if @scanner.scan(/\)/)
        return {}
      end

      pairs = {}
      loop do
        key = parse_key_name
        expect!("=")
        value = parse_value
        pairs[key] = value
        skip_ws
        break if @scanner.scan(/\)/)
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
        break if @scanner.scan(/\}/)
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
      if @scanner.scan(/\(/)
        parse_object
      elsif @scanner.scan(/\[/)
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

      start_pos = @scanner.pos
      
      # If we allow key boundary, we need to be careful not to consume the next key
      # This is the tricky part. The original implementation scanned ahead.
      # With StringScanner, we can scan until a terminator or whitespace.
      
      token = if allow_key_boundary
                scan_until_boundary_or_terminator
              else
                scan_until_terminator
              end

      raise ParseError, "Empty value at #{start_pos}" if token.nil? || token.empty?

      convert_scalar(token)
    end

    def scan_until_terminator
      # Scan until we hit a terminator char, whitespace, or structure char
      # Terminators: , ; ) ] }
      # Structure: ( [ {
      # Whitespace
      
      @scanner.scan(/[^,;\]\}\)\(\[\{\s]+/)
    end

    def scan_until_boundary_or_terminator
      # This is complex because "key=" looks like a scalar "key" followed by "="
      # But "value" followed by "key=" means "value" ends before "key".
      # The original logic used `next_key_index`.
      
      # Let's try to replicate the logic:
      # Scan characters that are safe for keys/values.
      # If we see something that looks like a key start, check if it is followed by [(=
      
      start_pos = @scanner.pos
      
      # Fast path: scan until something interesting happens
      chunk = @scanner.scan(/[0-9A-Za-z_.:-]+/)
      return nil unless chunk
      
      # Now we might have consumed too much if the chunk contains a key.
      # e.g. "valuekey=" -> chunk is "valuekey"
      # We need to check if there is a split point inside `chunk` or if `chunk` itself is followed by [(=
      
      # Actually, the original logic was:
      # Find the *first* position where a valid key starts AND is followed by [(=
      
      # Let's re-implement `next_key_index` logic but using the scanner's string
      
      rest_of_string = @scanner.string[@scanner.pos..-1]
      # But we also need to consider the chunk we just scanned? 
      # No, `scan_until_boundary_or_terminator` is called when we are at the start of a scalar.
      
      # Let's reset and do it properly.
      @scanner.pos = start_pos
      
      full_scalar = scan_until_terminator
      return nil unless full_scalar
      
      # Now check if `full_scalar` contains a key boundary
      # A key boundary is a substring that matches SAFE_TOKEN and is followed by [(=
      
      # We need to look at `full_scalar` + whatever follows (whitespace?) + [(=
      # But `scan_until_terminator` stops at whitespace.
      
      # If `full_scalar` is "valuekey", and next char is "=", then "key" is the key.
      # But wait, "value" and "key" must be separated? 
      # In CTON, "valuekey=..." is ambiguous if no separator.
      # The README says: "Removing every newline makes certain inputs ambiguous... The default separator avoids that... You may pass separator: ''... decoding such strings is only safe if you can guarantee extra quoting or whitespace".
      
      # So if we are in `allow_key_boundary` mode (top level), we must look for embedded keys.
      
      # Let's look for the pattern inside the text we just consumed + lookahead.
      # Actually, the original `next_key_index` scanned from the current position.
      
      # Let's implement a helper that searches for the boundary in the remaining string
      # starting from `start_pos`.
      
      boundary_idx = find_key_boundary(start_pos)
      
      if boundary_idx
        # We found a boundary at `boundary_idx`.
        # The scalar ends at `boundary_idx`.
        length = boundary_idx - start_pos
        @scanner.pos = start_pos
        token = @scanner.peek(length)
        @scanner.pos += length
        token
      else
        # No boundary found, so the whole thing we scanned is the token
        # We already scanned it into `full_scalar` but we need to put the scanner in the right place.
        # Wait, I reset the scanner.
        @scanner.pos = start_pos + full_scalar.length
        full_scalar
      end
    end

    def find_key_boundary(from_index)
      str = @scanner.string
      len = str.length
      idx = from_index
      
      # We are looking for a sequence that matches SAFE_KEY followed by [(=
      # But we are currently parsing a scalar.
      
      # Optimization: we only care about boundaries that appear *before* any terminator/whitespace.
      # Because if we hit a terminator/whitespace, the scalar ends anyway.
      
      # So we only need to check inside the `scan_until_terminator` range?
      # No, because "valuekey=" has no terminator/whitespace between value and key.
      
      while idx < len
        char = str[idx]
        
        # If we hit a terminator or whitespace, we stop looking for boundaries 
        # because the scalar naturally ends here.
        if TERMINATORS.include?(char) || whitespace?(char) || "([{".include?(char)
           return nil
        end
        
        # Check if a key starts here
        if safe_key_char?(char)
          # Check if this potential key is followed by [(=
          # We need to scan this potential key
          key_end = idx
          while key_end < len && safe_key_char?(str[key_end])
            key_end += 1
          end
          
          # Check what follows
          next_char_idx = key_end
          # Skip whitespace after key? No, keys are immediately followed by [(= usually?
          # The original `next_key_index` did NOT skip whitespace after the key candidate.
          # "next_char = @source[idx]" (where idx is after key)
          
          if next_char_idx < len
             next_char = str[next_char_idx]
             if ["(", "[", "="].include?(next_char)
               # Found a boundary!
               # But wait, is this the *start* of the scalar?
               # If idx == from_index, then the scalar IS the key? No, that means we are at the start.
               # If we are at the start, and it looks like a key, then it IS a key, so we should have parsed it as a key?
               # No, `parse_scalar` is called when we expect a value.
               # If we are parsing a document "key=valuekey2=value2", we are parsing "valuekey2".
               # "key2" is the next key. So "value" is the scalar.
               # So if idx > from_index, we found a split.
               
               return idx if idx > from_index
             end
          end
          
          # If not a boundary, we continue scanning from inside the key?
          # "valuekey=" -> at 'k', key is "key", followed by '=', so split at 'k'.
          # "valukey=" -> at 'l', key is "lukey", followed by '=', so split at 'l'.
          # This seems to imply we should check every position?
          # The original code:
          # if safe_key_char?(char)
          #   start = idx
          #   idx += 1 while ...
          #   if start > from_index && ... return start
          #   idx = start + 1  <-- This is important! It backtracks to check nested keys.
          #   next
          
          # Yes, we need to check every position.
          
          # Optimization: The key must end at `key_end`.
          # If `str[key_end]` is not [(=, then this `key_candidate` is not a key.
          # But maybe a suffix of it is?
          # e.g. "abc=" -> "abc" followed by "=". Split at start? No.
          # "a" followed by "bc="? No.
          
          # Actually, if we find a valid key char, we scan to the end of the valid key chars.
          # Let's say we have "abc=def".
          # At 'a': key is "abc". Next is "=". "abc" is a key.
          # If we are at start (from_index), then the whole thing is a key?
          # But we are parsing a scalar.
          # If `parse_scalar` sees "abc=", and `allow_key_boundary` is true.
          # Does it mean "abc" is the scalar? Or "abc" is the next key?
          # If "abc" is the next key, then the scalar before it is empty?
          # "key=abc=def" -> key="key", value="abc", next_key="def"? No.
          # "key=value next=val" -> value="value", next="next".
          # "key=valuenext=val" -> value="value", next="next".
          
          # So if we find a key boundary at `idx`, it means the scalar ends at `idx`.
          
          # Let's stick to the original logic:
          # Scan the maximal sequence of safe chars.
          # If it is followed by [(=, then it IS a key.
          # If it starts after `from_index`, then we found the boundary.
          # If it starts AT `from_index`, then... what?
          # If we are parsing a scalar, and we see "key=...", then the scalar is empty?
          # That shouldn't happen if we called `parse_scalar`.
          # Unless `parse_document` called `parse_value_for_key` -> `parse_scalar`.
          # But `parse_document` calls `parse_key_name` first.
          # So we are inside `parse_value`.
          
          # Example: "a=1b=2".
          # parse "a", expect "=", parse value.
          # value starts at "1".
          # "1" is safe char. "1b" is safe.
          # "b" is safe.
          # At "1": max key is "1b". Next is "=". "1b" is a key? Yes.
          # Is "1b" followed by "="? Yes.
          # Does it start > from_index? "1" is at from_index. No.
          # So "1b" is NOT a boundary.
          # Continue to next char "b".
          # At "b": max key is "b". Next is "=". "b" is a key.
          # Does it start > from_index? Yes ("b" index > "1" index).
          # So boundary is at "b".
          # Scalar is "1".
          
          # So the logic is:
          # For each char at `idx`:
          #   If it can start a key:
          #     Find end of key `end_key`.
          #     If `str[end_key]` is [(= :
          #       If `idx > from_index`: return `idx`.
          #   idx += 1
          
          # But wait, "1b" was a key candidate.
          # If we advanced `idx` to `end_key`, we would skip "b".
          # So we must NOT advance `idx` to `end_key` blindly.
          # We must check `idx`, then `idx+1`, etc.
          
          # But `safe_key_char?` is true for all chars in "1b".
          # So we check "1...", then "b...".
          
          # Correct.
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
        if @scanner.eos?
          raise ParseError, "Unterminated string"
        end
        
        char = @scanner.getch
        
        if char == '\\'
          escaped = @scanner.getch
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
      end
      buffer
    end

    def parse_key_name
      skip_ws
      token = @scanner.scan(/[0-9A-Za-z_.:-]+/)
      raise ParseError, "Invalid key" if token.nil?
      symbolize_names ? token.to_sym : token
    end

    def parse_integer_literal
      token = @scanner.scan(/-?\d+/)
      raise ParseError, "Expected digits" if token.nil?
      Integer(token, 10)
    rescue ArgumentError
      raise ParseError, "Invalid length literal"
    end

    def symbolize_keys(row)
      symbolize_names ? row.transform_keys(&:to_sym) : row
    end

    def expect!(char)
      skip_ws
      unless @scanner.scan(Regexp.new(Regexp.escape(char)))
        raise ParseError, "Expected #{char.inspect}, got #{@scanner.peek(1).inspect}"
      end
    end

    def skip_ws
      @scanner.skip(/\s+/)
    end

    def whitespace?(char)
      char == " " || char == "\t" || char == "\n" || char == "\r"
    end

    def key_ahead?
      # Check if the next token looks like a key followed by [(=
      # We need to preserve position
      pos = @scanner.pos
      skip_ws
      
      # Scan a key
      if @scanner.scan(/[0-9A-Za-z_.:-]+/)
        # Check what follows
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
