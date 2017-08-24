module AE

  module ConsolePlugin

    class Feature

      # @!method initialize(app)
      # The constructor of the feature is passed an struct giving access to 
      # various parts of the console on which you can register observers.
      # Currently these are: consoles, settings, plugin
      # (See core.rb and other source files for available events)
      # @param [Struct]
      # @return [Feature]

      # @!method get_javascript_path()
      # Return the path to the feature's accompagnying JavaScript file to be loaded into the html dialog.
      # @return [String]

      # @!method get_javascript_string()
      # Return a string of JavaScript to be loaded into the html dialog.
      # This method can be used for short scripts.
      # @return [String]
      #
      # @example
      #   def get_javascript_string
      #   <<-'JAVASCRIPT'
      #     require(['app'], function (app) {
      #       alert('Hello!');
      #     }
      #   JAVASCRIPT
      #   end

    end

  end # module ConsolePlugin

end # module AE
