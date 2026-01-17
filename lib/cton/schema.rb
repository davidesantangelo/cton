# frozen_string_literal: true

module Cton
  module Schema
    PATH_ROOT = "root"

    class Error
      attr_reader :path, :message, :expected, :actual

      def initialize(path:, message:, expected: nil, actual: nil)
        @path = path
        @message = message
        @expected = expected
        @actual = actual
      end

      def to_s
        details = []
        details << "expected #{expected}" if expected
        details << "got #{actual}" if actual
        suffix = details.empty? ? "" : " (#{details.join(", ")})"
        "#{path}: #{message}#{suffix}"
      end

      def to_h
        {
          path: path,
          message: message,
          expected: expected,
          actual: actual
        }
      end
    end

    class Result
      attr_reader :errors

      def initialize(errors = [])
        @errors = errors.freeze
      end

      def valid?
        errors.empty?
      end

      def to_s
        return "Valid schema" if valid?

        messages = errors.map(&:to_s)
        format("Schema violations:\n  %<messages>s", messages: messages.join("\n  "))
      end
    end

    class Node
      def validate(_value, _path, _errors)
        raise NotImplementedError
      end
    end

    class AnySchema < Node
      def validate(_value, _path, _errors); end
    end

    class NullableSchema < Node
      def initialize(inner)
        @inner = inner
      end

      def validate(value, path, errors)
        return if value.nil?

        @inner.validate(value, path, errors)
      end
    end

    class OptionalSchema < Node
      def initialize(inner)
        @inner = inner
      end

      def validate(value, path, errors)
        return if value.nil?

        @inner.validate(value, path, errors)
      end
    end

    class ScalarSchema < Node
      DEFAULT_TYPES = [String, Numeric, TrueClass, FalseClass, NilClass].freeze

      def initialize(types: nil, enum: nil)
        @types = types.nil? || types.empty? ? DEFAULT_TYPES : types
        @enum = enum
      end

      def validate(value, path, errors)
        if @enum && !@enum.include?(value)
          errors << Error.new(
            path: path,
            message: "Unexpected value",
            expected: @enum.inspect,
            actual: value.inspect
          )
          return
        end

        return if @types.any? { |type| value.is_a?(type) }

        errors << Error.new(
          path: path,
          message: "Unexpected type",
          expected: @types.map(&:name).join(" | "),
          actual: value.class.name
        )
      end
    end

    class ObjectSchema < Node
      def initialize(required:, optional:, allow_extra: false)
        @required = required.transform_keys(&:to_s)
        @optional = optional.transform_keys(&:to_s)
        @allow_extra = allow_extra
      end

      def validate(value, path, errors)
        unless value.is_a?(Hash)
          errors << Error.new(
            path: path,
            message: "Expected object",
            expected: "Hash",
            actual: value.class.name
          )
          return
        end

        value_keys = value.keys.map(&:to_s)
        @required.each_key do |key|
          next if value_keys.include?(key)

          errors << Error.new(
            path: "#{path}.#{key}",
            message: "Missing required key",
            expected: key,
            actual: "missing"
          )
        end

        schemas = @required.merge(@optional)
        schemas.each do |key, schema|
          next unless value_keys.include?(key)

          schema.validate(fetch_value(value, key), "#{path}.#{key}", errors)
        end

        return if @allow_extra

        extras = value_keys - schemas.keys
        extras.each do |key|
          errors << Error.new(
            path: "#{path}.#{key}",
            message: "Unexpected key",
            expected: schemas.keys.join(", "),
            actual: key
          )
        end
      end

      private

      def fetch_value(hash, key)
        return hash[key] if hash.key?(key)

        hash[key.to_sym]
      end
    end

    class ArraySchema < Node
      def initialize(item_schema:, length: nil, min: nil, max: nil)
        @item_schema = item_schema || AnySchema.new
        @length = length
        @min = min
        @max = max
      end

      def validate(value, path, errors)
        unless value.is_a?(Array)
          errors << Error.new(
            path: path,
            message: "Expected array",
            expected: "Array",
            actual: value.class.name
          )
          return
        end

        if @length && value.length != @length
          errors << Error.new(
            path: path,
            message: "Unexpected array length",
            expected: @length,
            actual: value.length
          )
        end

        if @min && value.length < @min
          errors << Error.new(
            path: path,
            message: "Array length below minimum",
            expected: @min,
            actual: value.length
          )
        end

        if @max && value.length > @max
          errors << Error.new(
            path: path,
            message: "Array length above maximum",
            expected: @max,
            actual: value.length
          )
        end

        value.each_with_index do |item, index|
          @item_schema.validate(item, "#{path}[#{index}]", errors)
        end
      end
    end

    module DSL
      def object(allow_extra: false, &block)
        builder = ObjectBuilder.new(allow_extra: allow_extra)
        builder.instance_eval(&block) if block
        builder.to_schema
      end

      def array(length: nil, min: nil, max: nil, of: nil, &block)
        builder = ArrayBuilder.new(length: length, min: min, max: max)
        builder.items(of) if of
        builder.instance_eval(&block) if block
        builder.to_schema
      end

      def nullable(schema)
        NullableSchema.new(schema)
      end

      def optional(schema)
        OptionalSchema.new(schema)
      end

      def any
        AnySchema.new
      end

      def scalar(*types, enum: nil)
        ScalarSchema.new(types: normalize_types(types), enum: enum)
      end

      def enum(*values)
        ScalarSchema.new(types: values.map(&:class).uniq, enum: values)
      end

      def string
        ScalarSchema.new(types: [String])
      end

      def integer
        ScalarSchema.new(types: [Integer])
      end

      def float
        ScalarSchema.new(types: [Float])
      end

      def number
        ScalarSchema.new(types: [Numeric])
      end

      def boolean
        ScalarSchema.new(types: [TrueClass, FalseClass])
      end

      def null
        ScalarSchema.new(types: [NilClass])
      end

      private

      def normalize_types(types)
        return nil if types.empty?

        types.flat_map do |type|
          case type
          when :boolean
            [TrueClass, FalseClass]
          when :null
            [NilClass]
          when :number
            [Numeric]
          else
            type
          end
        end
      end
    end

    class Builder
      include DSL
    end

    class ObjectBuilder < Builder
      def initialize(allow_extra: false)
        @required = {}
        @optional = {}
        @allow_extra = allow_extra
      end

      def key(name, schema = nil, &)
        @required[name.to_s] = resolve_schema(schema, &)
      end

      def optional(name, schema = nil, &)
        @optional[name.to_s] = resolve_schema(schema, &)
      end

      def allow_extra_keys!
        @allow_extra = true
      end

      def to_schema
        ObjectSchema.new(required: @required, optional: @optional, allow_extra: @allow_extra)
      end

      private

      def resolve_schema(schema, &block)
        return schema if schema
        return Builder.new.instance_eval(&block) if block

        AnySchema.new
      end
    end

    class ArrayBuilder < Builder
      def initialize(length: nil, min: nil, max: nil)
        @length = length
        @min = min
        @max = max
        @item_schema = nil
      end

      def items(schema = nil, &)
        @item_schema = schema || Builder.new.instance_eval(&)
      end
      alias of items

      def to_schema
        ArraySchema.new(item_schema: @item_schema, length: @length, min: @min, max: @max)
      end
    end

    def self.define(&)
      schema = Builder.new.instance_eval(&)
      raise ArgumentError, "Schema definition must return a schema" unless schema.is_a?(Node)

      schema
    end
  end
end
