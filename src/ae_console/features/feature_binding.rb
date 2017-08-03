module AE

  module ConsolePlugin

    class FeatureBinding

      def initialize(app)
        @app = app
        app.settings[:binding] ||= 'global'

        app.plugin.on(:console_added, &method(:initialize_console))

        # Validate initial binding loaded from settings.
        begin
          string_to_binding(app.settings[:binding])
        rescue StandardError
          app.settings[:binding] = 'global'
        end
      end

      def initialize_console(console)
        dialog = console.dialog
        dialog.on('set_binding') { |action_context, string|
          begin
            console.instance_variable_set(:@binding, string_to_binding(string))
            action_context.resolve
          rescue StandardError, Exception => e
            action_context.reject
          end
        }
        # Initialize binding in this new console instance.
        console.instance_variable_set(:@binding, string_to_binding(@app.settings[:binding])) rescue nil
      end

      def string_to_binding(string)
        if string == 'global'
          return TOPLEVEL_BINDING
        else
          # Allow global, class and instance variables, also nested modules or classes ($, @@, @, ::).
          # Do not allow any syntactic characters like braces or operators etc.
          string = string[/(\$|@@?)?[^\!\"\'\`\@\$\%\|\&\/\(\)\[\]\{\}\,\;\?\<\>\=\+\-\*\/\#\~\\]+/] #"
          # Instead of `object = eval(string, TOPLEVEL_BINDING)`, use Autocompleter to resolve the expression.
          tokens = string.split(/\:\:|\.|\s/)
          classification = Autocompleter.resolve_tokens(tokens, TOPLEVEL_BINDING)
          object = (classification.is_a?(Autocompleter::TokenClassificationByObject)) ? classification.object : nil
          raise StandardError('Binding object could not be found') if object.nil?
          # Get the binding of the object.
          return self.class.object_binding(object)
        end
      end

      def get_javascript_string
<<JAVASCRIPT
requirejs(['app', 'bridge'], function (app, Bridge) {
    var bindingProperty = app.settings.getProperty('binding', 'global');
    app.consoleMenu.addProperty(bindingProperty);

    var bindingElementOldValue = bindingProperty.getValue();
    bindingProperty.addListener('change', function (newValue) {
        Bridge.get('set_binding', newValue).then(function () {
            bindingElementOldValue = newValue;
        }, function (error) {
            // Set the property (and input element) back to its old, valid value.
            window.setTimeout(function(){
              bindingProperty.setValue(bindingElementOldValue);
            }, 0);
        });
    });
});
JAVASCRIPT
      end

      ObjectPointer ||= Struct.new(:value).new(nil)

    end # class FeatureBinding

  end # module ConsolePlugin

end # module AE

# Get an object's binding with correct the nesting, as if 'binding' was called
# in the original class definition.
# @param object [Object]
# @return [Binding]
def (AE::ConsolePlugin::FeatureBinding).object_binding(object)
  return case object
  when Class
    eval("class #{object.name};binding;end")
  when Module
    eval("module #{object.name};binding;end")
  else
    AE::ConsolePlugin::FeatureBinding::ObjectPointer.value = object # Alternative to using a global variable
    eval("class #{object.class.name}; ::AE::ConsolePlugin::FeatureBinding::ObjectPointer.value.instance_eval{binding}; end")
  end
end
