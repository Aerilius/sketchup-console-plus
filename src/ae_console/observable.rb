module AE

  module ConsolePlugin

    module Observable

      # When extended in a module/class as class methods
      def self.extended(containing_class)
        containing_class.instance_variable_set(:@listeners, {})
        nil
      end

      # When included in a class as instance methods. Containing class's constructor should call super()
      def initialize
        @listeners = {}
        super
      end

      def add_listener(event_name, &block)
        event_name = event_name.to_sym
        @listeners ||= {}
        @listeners[event_name] ||= []
        @listeners[event_name] << block
        nil
      end
      alias_method :on, :add_listener

      def remove_listener(event_name, block=nil, &_block)
        event_name = event_name.to_sym
        return unless @listeners && @listeners.include?(event_name)
        block = _block if block_given?
        if block
          @listeners[event_name].delete(block)
        else
          @listeners.delete(event_name)
        end
        nil
      end
      alias_method :off, :remove_listener

      private

      def trigger(event_name, *arguments)
        event_name = event_name.to_sym
        return unless @listeners && @listeners.include?(event_name)
        @listeners[event_name].each{ |block|
          block.call(*arguments)
        }
        nil
      end

    end

  end # module ConsolePlugin

end # module AE
