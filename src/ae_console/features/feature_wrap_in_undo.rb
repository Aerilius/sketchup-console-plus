module AE

  module ConsolePlugin

    class FeatureWrapInUndo

      def initialize(app)
        @app = app
        @undo_current_operation = app.settings[:wrap_in_undo] ||= false
        @model = Sketchup.active_model
        @undo_counter = 0

        app.plugin.on(:console_added, &method(:initialize_console))
      end


      def initialize_console(console)
        console.on(:eval) { |command, metadata|
          @undo_current_operation = @app.settings[:wrap_in_undo]
          if @undo_current_operation
            @model = Sketchup.active_model # FIXME: in a MDI, we need to choose the model to which the command is going to modify.
            @undo_counter += 1
            operation_name = TRANSLATE['Ruby Console operation %0', @undo_counter]
            @model.start_operation(operation_name, true)
          end
        }

        console.on(:result) { |result, metadata|
          if @undo_current_operation
            @model.commit_operation
          end
        }

        console.on(:error) { |exception, metadata|
          if @undo_current_operation
            @model.abort_operation
          end
        }
      end

      def get_javascript_string
<<JAVASCRIPT
requirejs(['app'], function (app) {
    var wrapInUndoProperty = app.settings.getProperty('wrap_in_undo', false);
    app.consoleMenu.addProperty(wrapInUndoProperty);
});
JAVASCRIPT
      end

    end # class FeatureWrapInUndo

  end # module ConsolePlugin

end # module AE
