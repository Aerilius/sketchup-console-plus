module AE

  module ConsolePlugin

    class FeatureAutocomplete

      require(File.join(PATH, 'features', 'autocompleter.rb'))
      require(File.join(PATH, 'features', 'docprovider.rb'))
      require(File.join(PATH, 'features', 'api_usage_counter.rb'))

      def initialize(app)
        @api_usage_counter = nil
        number_of_consoles = 0
        
        app.plugin.on(:console_added){ |console|
          @api_usage_counter = ApiUsageCounter.new.read if number_of_consoles == 0
          number_of_consoles += 1
          dialog = console.dialog

          dialog.on('autocomplete_tokens') { |action_context, tokens, prefix|
            binding = console.instance_variable_get(:@binding)
            autocomplete_token_list(action_context, tokens, prefix, binding)
          }

          dialog.on('autocomplete_filepath') { |action_context, prefix|
            autocomplete_filepath(action_context, prefix)
          }

          dialog.on('autocompletion_inserted') { |action_context, docpath|
            @api_usage_counter.used(docpath)
          }

        }
        
        app.plugin.on(:console_closed){ |console|
          number_of_consoles -= 1
          @api_usage_counter.save if number_of_consoles == 0
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
        total_tokens_count = @api_usage_counter.instance_variable_get(:@data).count #DocProvider.instance_variable_get(:@apis).count
        total_usage_count = @api_usage_counter.get_total_count
        mean = total_usage_count / (total_tokens_count | 1)
        completions.map!{ |classification|
          confidence_score = 3 - classification.inherited
          usage_score = @api_usage_counter.get_count(classification.docpath) / (mean | 1)
          alphabetical_score = 1 - string_to_positional_fraction(classification.token.to_s)
          score = 1000 * confidence_score + 10 * usage_score + alphabetical_score
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
