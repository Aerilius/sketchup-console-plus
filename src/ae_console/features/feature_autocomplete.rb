module AE

  module ConsolePlugin

    class FeatureAutocomplete

      require(File.join(PATH, 'features', 'autocompleter.rb'))
      require(File.join(PATH, 'features', 'docprovider.rb'))

      def initialize(app)
        app.plugin.on(:console_added){ |console|
          dialog = console.dialog

          dialog.on('autocomplete_token_list') { |action_context, tokens, prefix|
            binding = console.instance_variable_get(:@binding)
            autocomplete_token_list(action_context, tokens, prefix, binding)
          }
        }
      end

      def autocomplete_token_list(action_context, tokens, prefix, binding)
        # May raise Autocompleter::AutocompleterException
        completions = Autocompleter.complete(tokens, prefix, binding)
        completions.map!{ |classification|
          {
            :value   => classification.token, # the full token insert
            :caption => classification.token.to_s, # the displayed text, but must match the value (?)
            :meta    => TRANSLATE[classification.type.to_s], # or classification.class_path
            :score   => 1000,
            :docHTML => (DocProvider.get_documentation_html(classification.doc_path) rescue nil) # DocNotFoundError
          }
        }
        action_context.resolve completions
      end

      def get_javascript_path
        return 'feature_autocomplete.js'
      end

    end # class FeatureAutocomplete

  end # module ConsolePlugin

end # module AE
