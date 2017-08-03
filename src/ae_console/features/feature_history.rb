module AE

  module ConsolePlugin

    class FeatureHistory

      require(File.join(PATH, 'features', 'historyprovider.rb'))

      def initialize(app)
        app.plugin.on(:console_added){ |console|
          dialog = console.dialog

          # Create a HistoryProvider to load, record and save the history.
          history = HistoryProvider.new

          dialog.on('get_history') { |action_context|
            action_context.return history.to_a
          }

          dialog.on('push_to_history'){ |action_context, text|
            history.push(text)
          }

          console.on(:before_close) {
            history.save
            history.close
          }

        }
      end

      def get_javascript_path
        return 'feature_history.js'
      end

    end # class FeatureHistory

    register_feature(FeatureHistory)

  end # module ConsolePlugin

end # module AE
