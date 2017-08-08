module AE

  module ConsolePlugin

    require(File.join(PATH, 'features', 'docprovider.rb'))
    require(File.join(PATH, 'features', 'tokenclassification.rb'))

    module TokenResolver

      unless defined?(self::CONSTANT)
        CONSTANT = /^[A-Z]/
        GLOBAL_VARIABLE = /^\$/
        INSTANCE_VARIABLE = /^@[^@]/
        CLASS_VARIABLE = /^@@/
        METHOD = /^[^\d;,:#`'"=\.\{\}\(\)\]\$\?\\]/  #]/
        SCOPE_OPERATOR = /^\:\:$/
        METHOD_OPERATOR = /^\.$/
      end

      # Resolves a token list to a classification that wraps an token/object.
      # @param tokens [Array<String>]
      # @param binding [Binding]
      # @return [AE::ConsolePlugin::TokenClassification]
      # @raise TokenResolverError
      def self.resolve_tokens(tokens, binding=TOPLEVEL_BINDING)
        return ForwardEvaluationResolver.resolve_tokens(tokens, binding)
      end

      # @param path [String]
      # @raise [NameError]
      # @private
      def self.resolve_module_path(path)
        tokens = path.split('::')
        return tokens.reduce(::Object){ |modul, token| modul.const_get(token) }
      end

      class TokenResolverError < StandardError; end

      module ForwardEvaluationResolver

        # Resolves a token list to a classification by forward-evaluation.
        # That means the first token of an expression is evaluated to find the
        # corresponding object in object space. Based on its type, the subsequent
        # token is resolved to obtain its return type etc..
        # @param tokens [Array<String>]
        # @param binding [Binding]
        # @return [AE::ConsolePlugin::TokenClassification]
        # @raise TokenResolverError
        def self.resolve_tokens(tokens, binding)
          tokens = tokens.clone # We will mutate the array.
          first_token = tokens.shift
          classification = resolve_first_token(first_token, binding)
          tokens.each{ |token|
            case token
            when SCOPE_OPERATOR, METHOD_OPERATOR
              next
            else
              classification = classification.resolve(token)
            end
          }
          return classification
        rescue TokenClassification::TokenNotResolvedError => error
          repackaged_error = TokenResolverError.new(error)
          repackaged_error.set_backtrace(error.backtrace)
          raise repackaged_error
        end

        class << self

          private

          def resolve_first_token(token, binding)
            begin
              # Try to lookup the first token in ObjectSpace
              return resolve_identifier_in_scope(token, binding)
            rescue TokenResolverError => e
              # Try to lookup the first token in the documentation (likely to find only constants, module/class names)
              resolve_first_token_as_global_method(token)
            end
          end

          # Returns the object identified by a token in the context of binding.
          # @param token [String]
          # @param binding [Binding]
          # @return [TokenClassificationByObject]
          # @raise TokenResolverError
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
              raise TokenResolverError.new("No global variable found for `#{token}`") unless Kernel.global_variables.include?(token.to_sym)
              object = TOPLEVEL_BINDING.eval(token)
              return TokenClassificationByObject.new(token, :global_variable, '', object)
            when INSTANCE_VARIABLE
              raise TokenResolverError.new("No instance variable found for `#{token}`") unless context.instance_variable_defined?(token)
              object = context.instance_variable_get(token)
              namespace = context.class.name
              return TokenClassificationByObject.new(token, :instance_variable, namespace, object)
            when CLASS_VARIABLE
              context = context.class unless context.is_a?(Module)
              raise TokenResolverError.new("No class variable found for `#{token}`") unless context.class_variable_defined?(token)
              object = context.class_variable_get(token)
              namespace = (context == ::Object) ? '' : context.name
              return TokenClassificationByObject.new(token, :class_variable, namespace, object)
            else # Local variable or method
              if binding.eval('local_variables').include?(token.to_sym)
                object = binding.eval(token.to_s)
                return TokenClassificationByObject.new(token, :local_variable, '', object)
              elsif context.methods.include?(token.to_sym) || Kernel.methods.include?(token.to_sym)
                raise TokenResolverError.new("Unresolvable because `#{token}` is a method → Get type from docs")
              else
                raise TokenResolverError.new("No object found for `#{token}`")
              end
            end
          rescue NameError => error # from const_get, class_variable_get
            repackaged_error = TokenResolverError.new(error)
            repackaged_error.set_backtrace(error.backtrace)
            raise repackaged_error
          end

          def resolve_first_token_as_global_method(token)
            doc_info = DocProvider.get_info_for_docpath(token)
            # Try methods of global objects.
            doc_info = DocProvider.get_info_for_docpath("Object.#{token}") unless doc_info && [:type, :namespace, :return].all?{ |key| doc_info[:key] }
            doc_info = DocProvider.get_info_for_docpath("Object##{token}") unless doc_info && [:type, :namespace, :return].all?{ |key| doc_info[:key] }
            doc_info = DocProvider.get_info_for_docpath("Kernel.#{token}") unless doc_info && [:type, :namespace, :return].all?{ |key| doc_info[:key] }
            doc_info = DocProvider.get_info_for_docpath("Kernel##{token}") unless doc_info && [:type, :namespace, :return].all?{ |key| doc_info[:key] }
            raise TokenResolverError.new(("Doc info not found for `#{token}`")) unless doc_info && [:type, :namespace, :return].all?{ |key| doc_info[:key] }
            returned_types = DocProvider.extract_return_types(doc_info)
            returned_type = returned_types.first # TODO: consider all
            returned_is_instance = true # assume the method returns not a Class.
            return TokenClassificationByDoc.new(token, doc_info[:type], doc_info[:path], returned_type, returned_is_instance)
          end

        end

      end # module ForwardEvaluationResolver

    end # module Resolver

  end # module ConsolePlugin

end # module AE
