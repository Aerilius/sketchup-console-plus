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
        # Determine the longest prefix string that is common in all completions.
        # Create a completion entry and put it at the top of the list.
        longest_common_prefix = find_longest_common_prefix(completions)
        if !completions.include?(longest_common_prefix)
          longest_common_prefix = {
            :caption => longest_common_prefix[directory_prefix_length+1..-1],
            :value   => longest_common_prefix,
            :meta    => :filepath,
            :score   => 1000
          }
        else
          longest_common_prefix = nil
        end
        completions = completions.sort.each_with_index.map{ |filepath, index|
          {
            # Drop a directory path if contained within the prefix to make the displayed caption fit into available space.
            :caption => filepath[directory_prefix_length+1..-1],
            :value   => filepath,
            :meta    => :filepath,
            # Score the completion by alphabetic index.
            :score   => completions.length - index
          }
        }
        completions << longest_common_prefix unless longest_common_prefix.nil?
        action_context.resolve completions
      rescue Exception => e
        ConsolePlugin.error(e)
        action_context.reject
      end

      def find_longest_common_prefix(strings)
        return nil if strings.empty?
        reference = strings.min_by(&:length)
        pivot = 0
        while pivot < reference.length
          if strings.all?{ |string| string[pivot] == reference[pivot] }
            pivot += 1
          else
            break
          end
        end
        return reference[0...pivot]
      end

      def autocomplete_token_list(action_context, tokens, prefix, binding)
        # May raise Autocompleter::AutocompleterException
        completions = Autocompleter.complete(tokens, prefix, binding)
        completions.map!{ |classification|
          {
            :caption => classification.token,
            :value   => classification.token, # the full token insert
            :meta    => classification.namespace, # TRANSLATE[classification.type.to_s],
            :score   => (classification.docpath[/Sketchup|Geom|UI/]) ? 1000 : 100,
            :docHTML => (begin;DocProvider.get_documentation_html(classification);rescue DocProvider::DocNotFoundError;nil;end)
          }
        }
        action_context.resolve completions
      rescue Exception => e
        ConsolePlugin.error(e)
        action_context.reject
      end

      def get_javascript_path
        return 'feature_autocomplete.js'
      end

    end # class FeatureAutocomplete

  end # module ConsolePlugin

end # module AE
