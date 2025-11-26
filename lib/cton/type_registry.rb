# frozen_string_literal: true

module Cton
  # Registry for custom type serializers
  # Allows users to define how custom classes should be encoded to CTON
  class TypeRegistry
    # Handler wraps a serialization block with metadata
    Handler = Struct.new(:klass, :mode, :block, keyword_init: true)

    def initialize
      @handlers = {}
    end

    # Register a custom type handler
    #
    # @param klass [Class] The class to handle
    # @param as [Symbol] How to serialize: :object (Hash), :array, or :scalar
    # @param block [Proc] Transformation block receiving the value
    #
    # @example Register a Money class
    #   Cton.register_type(Money) do |money|
    #     { amount: money.cents, currency: money.currency }
    #   end
    #
    # @example Register a UUID as scalar
    #   Cton.register_type(UUID, as: :scalar) do |uuid|
    #     uuid.to_s
    #   end
    #
    def register(klass, as: :object, &block)
      raise ArgumentError, "Block required for type registration" unless block_given?
      raise ArgumentError, "as must be :object, :array, or :scalar" unless %i[object array scalar].include?(as)

      @handlers[klass] = Handler.new(klass: klass, mode: as, block: block)
    end

    # Unregister a type handler
    #
    # @param klass [Class] The class to unregister
    def unregister(klass)
      @handlers.delete(klass)
    end

    # Check if a handler exists for a class
    #
    # @param klass [Class] The class to check
    # @return [Boolean]
    def registered?(klass)
      @handlers.key?(klass) || find_handler_for_ancestors(klass)
    end

    # Transform a value using its registered handler
    # Returns the value unchanged if no handler is registered
    #
    # @param value [Object] The value to transform
    # @return [Object] The transformed value
    def transform(value)
      handler = find_handler(value.class)
      return value unless handler

      handler.block.call(value)
    end

    # Get the handler for a class
    #
    # @param klass [Class] The class to look up
    # @return [Handler, nil]
    def handler_for(klass)
      find_handler(klass)
    end

    # List all registered types
    #
    # @return [Array<Class>]
    def registered_types
      @handlers.keys
    end

    # Clear all registered handlers
    def clear!
      @handlers.clear
    end

    private

    def find_handler(klass)
      # Direct match
      return @handlers[klass] if @handlers.key?(klass)

      # Check ancestors (for inheritance support)
      find_handler_for_ancestors(klass)
    end

    def find_handler_for_ancestors(klass)
      klass.ancestors.each do |ancestor|
        return @handlers[ancestor] if @handlers.key?(ancestor)
      end
      nil
    end
  end

  # Global type registry instance
  @type_registry = TypeRegistry.new

  class << self
    # Access the global type registry
    #
    # @return [TypeRegistry]
    attr_reader :type_registry

    # Register a custom type handler
    #
    # @param klass [Class] The class to handle
    # @param as [Symbol] How to serialize: :object, :array, or :scalar
    # @param block [Proc] Transformation block
    #
    # @example
    #   Cton.register_type(Money) do |money|
    #     { amount: money.cents, currency: money.currency }
    #   end
    def register_type(klass, as: :object, &block)
      type_registry.register(klass, as: as, &block)
    end

    # Unregister a custom type handler
    #
    # @param klass [Class] The class to unregister
    def unregister_type(klass)
      type_registry.unregister(klass)
    end

    # Clear all custom type handlers
    def clear_type_registry!
      type_registry.clear!
    end
  end
end
