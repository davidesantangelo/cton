# frozen_string_literal: true

module Cton
  class StreamReader
    include Enumerable

    def initialize(io, separator: "\n", symbolize_names: false)
      @io = io
      @separator = separator
      @symbolize_names = symbolize_names
    end

    def each
      buffer = String.new
      @io.each_line(@separator) do |chunk|
        buffer << chunk
        next if buffer.strip.empty?

        yield Decoder.new(symbolize_names: @symbolize_names).decode(buffer)
        buffer.clear
      end

      return if buffer.strip.empty?

      yield Decoder.new(symbolize_names: @symbolize_names).decode(buffer)
    end
  end

  class StreamWriter
    def initialize(io, separator: "\n", **options)
      @io = io
      @separator = separator
      @options = options
      @encoder = Encoder.new(**options, separator: separator)
      @first = true
    end

    def write(value)
      @io << @separator unless @first
      @encoder.encode(value, io: @io)
      @first = false
    end
  end
end
