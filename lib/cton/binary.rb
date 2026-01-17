# frozen_string_literal: true

require "zlib"

module Cton
  module Binary
    MAGIC = "CTON".b
    VERSION = 1
    FLAG_COMPRESSED = 1

    module_function

    def dump(data, compress: true, **options)
      payload = Cton.dump(data, **options).b
      flags = 0

      if compress
        payload = Zlib.deflate(payload)
        flags |= FLAG_COMPRESSED
      end

      header = MAGIC + [VERSION, flags].pack("CC")
      header + encode_varint(payload.bytesize) + payload
    end

    def load(binary)
      source = binary.to_s.b
      raise Cton::Error, "Invalid CTON-B header" unless source.start_with?(MAGIC)

      version = source.getbyte(4)
      flags = source.getbyte(5)
      raise Cton::Error, "Unsupported CTON-B version" unless version == VERSION

      length, consumed = decode_varint(source, 6)
      payload_start = 6 + consumed
      payload = source.byteslice(payload_start, length)
      raise Cton::Error, "Invalid CTON-B payload length" if payload.nil? || payload.bytesize < length

      payload = Zlib.inflate(payload) if (flags & FLAG_COMPRESSED).positive?

      Cton.load(payload)
    end

    def encode_varint(value)
      bytes = []
      remaining = value
      while remaining >= 0x80
        bytes << ((remaining & 0x7f) | 0x80)
        remaining >>= 7
      end
      bytes << remaining
      bytes.pack("C*")
    end

    def decode_varint(source, offset)
      result = 0
      shift = 0
      index = offset

      loop do
        byte = source.getbyte(index)
        raise Cton::Error, "Invalid CTON-B varint" unless byte

        result |= (byte & 0x7f) << shift
        index += 1
        break if (byte & 0x80).zero?

        shift += 7
      end

      [result, index - offset]
    end
  end
end
