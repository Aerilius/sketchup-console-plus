module AE

  module ConsolePlugin

    require(File.join(PATH, 'features', 'docprovider.rb'))
    require(File.join(PATH, 'features', 'tokenclassification.rb'))

    # This module suggests completions from the live ObjectSpace using Ruby's reflection methods.
    # This way we get highly relevant suggestions that not only match alphabetically to the input,
    # but also to what is valid in the current context.
    module Autocompleter

      unless defined?(self::CONSTANT)
        CONSTANT = /^[A-Z]/
        GLOBAL_VARIABLE = /^\$/
        INSTANCE_VARIABLE = /^@[^@]/
        CLASS_VARIABLE = /^@@/
        METHOD = /^[^\d;,:#`'"=\.\{\}\(\)\]\$\?\\]/  #]/
        SCOPE_OPERATOR = /^\:\:$/
        METHOD_OPERATOR = /^\.$/
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
          classification = resolve_tokens(tokens, binding)
          completions = classification.get_completions(prefix)
        end
        return completions
      rescue TokenClassification::TokenNotResolvedError, AutocompleterError, NameError => e
        return []
      end

      # Resolves a token list to a classification that wraps an token/object.
      # @param tokens [Array<String>]
      # @param binding [Binding]
      # @return [AE::ConsolePlugin::TokenClassification]
      # @raise AutocompleterError
      def self.resolve_tokens(tokens, binding=TOPLEVEL_BINDING)
        tokens = tokens.clone # We will mutate the array.
        first_token = tokens.shift
        classification = resolve_token(first_token, binding)
        tokens.each{ |token|
          case token
          when SCOPE_OPERATOR, METHOD_OPERATOR
            next
          else
            classification = classification.resolve(token)
          end
        }
        return classification
      end

      class AutocompleterError < StandardError; end

      class << self

        private

        def resolve_token(token, binding)
          begin
            # Try to lookup the first token in ObjectSpace
            return resolve_identifier_in_scope(token, binding)
          rescue AutocompleterError => e
            # Try to lookup the first token in the documentation (likely to find only constants, module/class names)
            doc_info = DocProvider.get_info_for_docpath(token)
            if doc_info && doc_info[:path]
              returned_types = Autocompleter.parse_return_types(doc_info[:return].first)
              returned_type = returned_types.first # TODO: consider all
              returned_is_instance = true # assume the method returns not a Class.
              return TokenClassificationByDoc.new(token, doc_info[:type], doc_info[:path], returned_type, returned_is_instance)
            else
              doc_info = DocProvider.get_info_for_docpath("Object.#{token}") if doc_info.nil? || doc_info[:path].nil?
              doc_info = DocProvider.get_info_for_docpath("Object##{token}") if doc_info.nil? || doc_info[:path].nil?
              doc_info = DocProvider.get_info_for_docpath("Kernel.#{token}") if doc_info.nil? || doc_info[:path].nil?
              doc_info = DocProvider.get_info_for_docpath("Kernel##{token}") if doc_info.nil? || doc_info[:path].nil?
              raise AutocompleterError.new(("Doc info not found for `#{token}`")) if doc_info.nil? || doc_info[:path].nil?
              returned_types = Autocompleter.parse_return_types(doc_info[:return].first)
              returned_type = returned_types.first # TODO: consider all
              returned_is_instance = true # assume the method returns not a Class.
              return TokenClassificationByDoc.new(token, doc_info[:type], doc_info[:path], returned_type, returned_is_instance)
            end
          end
        end

        # Returns the object identified by a token in the context of binding.
        # @param token [String]
        # @param binding [Binding]
        # @return [TokenClassificationByObject]
        # @raise AutocompleterError
        def resolve_identifier_in_scope(token, binding)
          context = binding.eval('self')
          case token
          when CONSTANT
            context = context.class unless context.is_a?(Module)
            object = context.const_get(token)
            namespace = (context == ::Object) ? '' : context.name
            type = (object.is_a?(Class)) ? :class : (object.is_a?(Module)) ? :module : :constant
            return TokenClassificationByObject.new(token, type, namespace, object)
          when GLOBAL_VARIABLE
            raise AutocompleterError.new("No global variable found for `#{token}`") unless Kernel.global_variables.include?(token.to_sym)
            object = TOPLEVEL_BINDING.eval(token)
            return TokenClassificationByObject.new(token, :global_variable, '', object)
          when INSTANCE_VARIABLE
            raise AutocompleterError.new("No instance variable found for `#{token}`") unless context.instance_variable_defined?(token)
            object = context.instance_variable_get(token)
            namespace = context.class.name
            return TokenClassificationByObject.new(token, :instance_variable, namespace, object)
          when CLASS_VARIABLE
            context = context.class unless context.is_a?(Module)
            raise AutocompleterError.new("No class variable found for `#{token}`") unless context.class_variable_defined?(token)
            object = context.class_variable_get(token)
            namespace = (context == ::Object) ? '' : context.name
            return TokenClassificationByObject.new(token, :class_variable, namespace, object)
          else # Local variable or method
            if binding.eval('local_variables').include?(token)
              object = binding.eval(token.to_s)
            return TokenClassificationByObject.new(token, :local_variable, '', object)
            elsif context.methods.include?(token.to_sym) || Kernel.methods.include?(token.to_sym)
              raise AutocompleterError.new("Unresolvable because `#{token}` is a method → Get type from docs")
              raise AutocompleterError.new("Unresolvable because `#{token}` is a method → Get type from docs")
            else
              raise AutocompleterError.new("No object found for `#{token}`")
            end
          end
        rescue NameError => error # from const_get, class_variable_get
          error2 = AutocompleterError.new(error)
          error2.set_backtrace(e.backtrace)
          raise error2
        end

        def get_completions(prefix, binding)
          context = binding.eval('self')
          context_class = (context.is_a?(Module)) ? context : context.class
          completions = []
          case prefix
          when CONSTANT
            # Resolve inheritance from outer module scopes.
            nesting = binding.eval('Module.nesting').reverse # includes context_class at the beginning (unless context_class == Object)
            nesting << Object # class of <main>
            nesting.each{ |modul|
              completions.concat(modul.constants.select{ |name| name.to_s.index(prefix) == 0 }.map{ |name|
                return_value = modul.const_get(name)
                type = (return_value.is_a?(Class)) ? :class : (return_value.is_a?(Module)) ? :module : :constant
                TokenClassification.new(name, type, (modul != ::Object) ? modul.name : '')
              })
            }
          when GLOBAL_VARIABLE
            completions.concat(Kernel.global_variables.select{ |name| name.to_s.index(prefix) == 0 }.map{ |name|
              TokenClassification.new(name, :global_variable, '')
            })
          when INSTANCE_VARIABLE
            completions.concat(context.instance_variables.select{ |name| name.to_s.index(prefix) == 0 }.map{ |name|
              TokenClassification.new(name, :instance_variable, context_class.name)
            })
          when CLASS_VARIABLE
            completions.concat(context.class_variables.select{ |name| name.to_s.index(prefix) == 0 }.map{ |name|
              TokenClassification.new(name, :class_variable, context_class.name)
            })
          else # Local variable
            completions.concat(binding.eval('local_variables').select{ |name| name.to_s.index(prefix) == 0 }.map{ |name|
              TokenClassification.new(name, :local_variable, context_class.name)
            })
            # Local methods
            is_instance = !context.is_a?(Module)
            type = (is_instance) ? :instance_method : (context.is_a?(Class)) ? :class_method : :module_function
            completions.concat((context.methods.concat(context.private_methods)).select{ |name| name.to_s.index(prefix) == 0 }.map{ |name|
              TokenClassification.new(name, type , context_class.name)
            })
          end
          return completions
        end

      end # class << self

      # @param path [String]
      # @raise [NameError]
      # @private
      def self.resolve_module_path(path)
        tokens = path.split('::')
        return tokens.reduce(::Object){ |modul, token| modul.const_get(token) }
      end

      # @param returned_types_string [String] A string of type declarations as parsed by yardoc.
      # @return [Array<String>]
      # @private
      def self.parse_return_types(return_types)
        return [] if return_types.nil?
        return return_types.map{ |s| parse_return_types(s) }.flatten if return_types.is_a?(Array)
        # Parse the yardoc type string
        # Remove nested types
        return_types.gsub!(/^\[|\]$/, '')
        return_types.gsub!(/<[^>]*>|\([^\)]*\)/, '')
        # Split into array of type names.
        return return_types.split(/,\s*/).compact.map{ |type|
          # Resolve type naming conventions to class names.
          case type
          when 'nil' then 'NilClass'
          when 'true' then 'TrueClass'
          when 'false' then 'FalseClass'
          when 'Boolean' then 'TrueClass' # TrueClass and FalseClass have same methods.
          when '0' then 'Fixnum'
          else type
          end
        }
      end

    end # module Autocompleter

  end

end
