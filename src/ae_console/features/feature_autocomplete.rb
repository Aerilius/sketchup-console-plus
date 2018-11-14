module AE

  module ConsolePlugin

    class FeatureAutocomplete

      require(File.join(PATH, 'features', 'autocompleter.rb'))
      require(File.join(PATH, 'features', 'docprovider.rb'))

      def initialize(app)
        app.plugin.on(:console_added){ |console|
          dialog = console.dialog

          dialog.on('autocomplete_tokens') { |action_context, tokens, prefix|
            binding = console.instance_variable_get(:@binding)
            autocomplete_token_list(action_context, tokens, prefix, binding)
          }

          dialog.on('autocomplete_filepath') { |action_context, prefix|
            autocomplete_filepath(action_context, prefix)
          }

        }
      end

      def autocomplete_filepath(action_context, prefix)
        completions = Autocompleter.complete_filepath(prefix)
        # Get the index of the last path separator so that we can drop the path from the displayed caption in the autocompletion list.
        directory_prefix_length = prefix.rindex('/') || -1
        completions = completions.sort.each_with_index.map{ |filepath, index|
          {
            # Drop a directory path if contained within the prefix to make the displayed caption fit into available space.
            :caption => filepath[directory_prefix_length+1..-1],
            :value   => filepath,
            :meta    => :filepath,
            # Score the completion by alphabetic index.
            :score   => (2000 + completions.length - index) + ((filepath[-1] == '/') ? 1000 : 0)
          }
        }
        action_context.resolve completions
      rescue Exception => e
        ConsolePlugin.error(e)
        action_context.reject
      end

      def autocomplete_token_list(action_context, tokens, prefix, binding)
        # May raise Autocompleter::AutocompleterException
        completions = Autocompleter.complete(tokens, prefix, binding)
        # Score the completions
        completions.map!{ |classification|
          confidence_score = 3 - classification.inherited
          alphabetical_score = 1 - string_to_positional_fraction(classification.token.to_s)
          score = 1000 * confidence_score + alphabetical_score
          doc_html = begin
            DocProvider.get_documentation_html(classification)
          rescue DocProvider::DocNotFoundError
            nil
          end
          {
            :caption => classification.token,
            :value   => classification.token, # the full token insert
            :meta    => classification.namespace, # TRANSLATE[classification.type.to_s],
            :score   => score,
            :docHTML => doc_html,
            :docpath => classification.docpath # custom attribute, not part of ace
          }
        }
        action_context.resolve completions
      rescue Exception => e
        ConsolePlugin.error(e)
        action_context.reject
      end

      def string_to_positional_fraction(string)
        return string.split(//).each_with_index.map{ |char, position|
          if char == ' '
            0
          else
            [0, [(char.upcase.ord - 65) / 26.0, 1].min].max * 10**(-position)
          end
        }.reduce(0, &:+)
      end

      def get_javascript_path
        return 'feature_autocomplete.js'
      end

    end # class FeatureAutocomplete

  end # module ConsolePlugin

end # module AE
