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
        return []
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
          prefix_regexp = Regexp.new('^' + prefix)
          case prefix
          when CONSTANT
            # Resolve inheritance from outer module scopes.
            nesting = binding.eval('Module.nesting').reverse # includes context_class at the beginning (unless context_class == Object)
            nesting << Object # class of <main>
            nesting.each{ |modul|
              completions.concat(modul.constants.grep(prefix_regexp).map{ |name|
                return_value = modul.const_get(name)
                type = (return_value.is_a?(Class)) ? :class : (return_value.is_a?(Module)) ? :module : :constant
                TokenClassification.new(name, type, (modul != ::Object) ? modul.name : '')
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
            is_instance = !context.is_a?(Module)
            type = (is_instance) ? :instance_method : (context.is_a?(Class)) ? :class_method : :module_function
            completions.concat((context.methods.concat(context.private_methods)).grep(prefix_regexp).map{ |name|
              TokenClassification.new(name, type , context_class.name)
            })
          end
          return completions
        end

      end # class << self

    end # module Autocompleter

  end

end
