module AE

  module ConsolePlugin

    require(File.join(PATH, 'features', 'docprovider.rb'))
    require(File.join(PATH, 'features', 'tokenclassification.rb'))
    require(File.join(PATH, 'features', 'tokenresolver.rb'))

    # This module suggests completions from the live ObjectSpace using Ruby's reflection methods.
    # This way we get highly relevant suggestions that not only match alphabetically to the input,
    # but also to what is valid in the current context.
    module Autocompleter

      unless defined?(self::CONSTANT)
        CONSTANT = /^[A-Z]/
        GLOBAL_VARIABLE = /^\$/
        INSTANCE_VARIABLE = /^@[^@]/
        CLASS_VARIABLE = /^@@/
      end

      # Returns possibilities how to complete a part of a token.
      # @param tokens [Array<String>] The tokens of an expression preceding the prefix
      # @param prefix [String] The string to complete.
      # @param binding [Binding]
      # @return [Array<TokenClassification>]
      def self.complete(tokens, prefix='', binding=TOPLEVEL_BINDING)
        if tokens.empty?
          completions = get_completions(prefix, binding)
        else
          classification = TokenResolver.resolve_tokens(tokens, binding)
          completions = classification.get_completions(prefix)
        end
        return completions
      rescue AutocompleterError, TokenResolver::TokenResolverError => e
        return (prefix.empty?) ? [] : get_completions_any_token_matches(prefix)
      end

      def self.complete_filepath(prefix)
        return ($LOAD_PATH + ['']).map{ |base|
          prefix_path = File.expand_path(prefix, base) # joins (base, prefix)
          offset = prefix_path.length - prefix.length
          paths = Dir.glob(prefix_path + '*')
          paths.map{ |path|
            path += '/' if File.directory?(path)
            path[offset..-1]
          }
        }.flatten
      end

      class AutocompleterError < StandardError; end

      class << self

        private

        # Returns possible completions in the global context.
        # @param prefix  [String]
        # @param binding [Binding]
        # @return [Array<TokenClassification>]
        def get_completions(prefix, binding)
          context = binding.eval('self')
          context_class = (context.is_a?(Module)) ? context : context.class
          completions = []
          begin
            prefix_regexp = non_verbose{ Regexp.new('^' + prefix) }
          rescue RegexpError
            # For example when prefix contains characters invalid for the encoding.
            # In that case, there are likely no completions anyways.
            return []
          end
          case prefix
          when CONSTANT
            # Resolve inheritance from outer module scopes.
            nesting = binding.eval('Module.nesting').reverse # includes context_class at the beginning (unless context_class == Object)
            nesting << Object # class of <main>
            nesting.each{ |modul|
              completions.concat(modul.constants.grep(prefix_regexp).map{ |name|
                return_value = modul.const_get(name)
                type = (return_value.is_a?(Class)) ? :class : (return_value.is_a?(Module)) ? :module : :constant
                TokenClassification.new(name, type, (modul != ::Object) ? modul.name : nil)
              })
            }
          when GLOBAL_VARIABLE
            completions.concat(Kernel.global_variables.grep(prefix_regexp).map{ |name|
              TokenClassification.new(name, :global_variable, '')
            })
          when INSTANCE_VARIABLE
            completions.concat(context.instance_variables.grep(prefix_regexp).map{ |name|
              TokenClassification.new(name, :instance_variable, context_class.name)
            })
          when CLASS_VARIABLE
            completions.concat(context_class.class_variables.grep(prefix_regexp).map{ |name|
              TokenClassification.new(name, :class_variable, context_class.name)
            })
          else # Local variable
            completions.concat(binding.eval('local_variables').grep(prefix_regexp).map{ |name|
              TokenClassification.new(name, :local_variable, context_class.name)
            })
            # Local methods
            # Take the method from the correct module if it comes from an included module.
            context_class.included_modules.each{ |modul|
              completions.concat(modul.methods.grep(prefix_regexp).map{ |method|
                TokenClassification.new(method, :instance_method, modul.name)
              })
            }
            # Methods defined in this class/module
            is_instance = !context.is_a?(Module)
            type = (is_instance) ? :instance_method : (context.is_a?(Class)) ? :class_method : :module_function
            completions.concat((context.methods.concat(context.private_methods)).grep(prefix_regexp).map{ |name|
              TokenClassification.new(name, type , context_class.name)
            })
          end
          if completions.empty?
            return get_completions_any_token_matches(prefix)
          end
          return completions
        end

        def get_completions_any_token_matches(prefix)
          return DocProvider.get_infos_for_token_prefix(prefix).map{ |doc_info|
            TokenClassification.new(doc_info[:name], doc_info[:type], doc_info[:namespace])
          }
        end

        def non_verbose(&block)
          # Warnings possible, but should not be visible in console.
          previous_verbosity = $VERBOSE
          $VERBOSE = nil
          result = block.call()
          $VERBOSE = previous_verbosity
          return result
        end

      end # class << self

    end # module Autocompleter

  end

end
