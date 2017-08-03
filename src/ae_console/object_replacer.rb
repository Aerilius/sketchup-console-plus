module AE

  module ConsolePlugin

    class ObjectReplacer

      def self.swap(identifier, replacement, context_object=nil, &block)
        context_object ||= TOPLEVEL_BINDING.eval('self')
        if identifier[/^\$/] &&
            ::Kernel.global_variables.include?(identifier.to_sym)
          original = eval(identifier)
          eval(@identifier.to_s + '= replacement')
          block.call
          eval(identifier.to_s + '= original')
        elsif identifier[/^@@[^@]/] && 
            context_object.is_a?(::Class) && 
            context_object.class_variables.include?(identifier.to_sym)
          original = context_object.class_variable_get(identifier)
          context_object.class_variable_set(identifier, replacement)
          block.call
          context_object.class_variable_set(identifier, original)
        elsif identifier[/^@[^@]/] && 
            context_object.instance_variables.include?(identifier.to_sym)
          original = context_object.instance_variable_get(identifier)
          context_object.instance_variable_set(identifier, replacement)
          block.call
          context_object.instance_variable_set(identifier, original)
        elsif context_object.respond_to?(identifier) && 
            context_object.respond_to?(identifier.to_s+'=')
          original = context_object.send(identifier)
          context_object.send(identifier.to_s+'=', replacement)
          block.call
          context_object.send(identifier.to_s+'=', original)
        else
          raise StandardError('Identifier not found')
        end
        nil
      end

      def initialize(identifier, replacement, context_object=nil)
        context_object ||= TOPLEVEL_BINDING.eval('self')
        @identifier = identifier.to_s
        @context_object = context_object
        @replacement = replacement
        @original = nil
        @type = nil
        if identifier[/^\$/] &&
            ::Kernel.global_variables.include?(identifier.to_sym)
          @type = :global_variable
          @original = eval(identifier)
        elsif identifier[/^@@[^@]/] && 
            context_object.is_a?(::Class) && 
            context_object.class_variables.include?(identifier.to_sym)
          @type = :class_variable
          @original = context_object.class_variable_get(identifier)
        elsif identifier[/^@[^@]/] && 
            context_object.instance_variables.include?(identifier.to_sym)
          @type = :instance_variable
          @original = context_object.instance_variable_get(identifier)
        elsif context_object.respond_to?(identifier) && 
            context_object.respond_to?(identifier.to_s+'=')
          @type = :accessor_method
          @original = context_object.send(identifier)
        else
          raise 'Identifier not found'
        end
      end

      def enable
        case @type
        when :global_variable   then eval(@identifier + '= @replacement')
        when :class_variable    then @context_object.class_variable_set(@identifier, @replacement)
        when :instance_variable then @context_object.instance_variable_set(@identifier, @replacement)
        when :accessor_method   then @context_object.send(@identifier+'=', @replacement)
        end
        return @replacement
      end

      def disable
        case @type
        when :global_variable   then eval(@identifier + '= @original')
        when :class_variable    then @context_object.class_variable_set(@identifier, @original)
        when :instance_variable then @context_object.instance_variable_set(@identifier, @original)
        when :accessor_method   then @context_object.send(@identifier+'=', @original)
        end
        return @original
      end

    end # class ObjectReplacer

  end # module ConsolePlugin

end # module AE
