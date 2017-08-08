module AE

  module ConsolePlugin

    require(File.join(PATH, 'features', 'docprovider.rb'))

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
      # @return [AE::ConsolePlugin::Autocompleter::TokenClassification]
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

      # TokenClassification identifies a token and the object (or type) that it 
      # refers to or returns.
      #
      # Here we make use of polymorphism to handle the different kind of 
      # information that we may have about a token. 
      # To use Ruby introspection, we ideally have a reference to the object
      # instance that it refers to, but a reference to its class is also enough.
      # Since Ruby is weakly typed, introspection does not allow to retrieve 
      # return types of methods (at most arity but not parameter types, by the 
      # way). In that case we fall back to use documentation to deduce the type 
      # of the potentially returned object.
      class TokenClassification

        class TokenNotResolvedError < StandardError; end

        attr_reader :token, :type, :namespace, :docpath

        def initialize(token, type, namespace)
          @token = token
          @type = type           # type of the token
          @namespace = namespace # path of object/class before the token, leading to the token
        end

        # Returns the class path and token.
        # @return [String]
        def docpath
          return case type
          when :constant, :module, :class
            (namespace.empty?) ? token : "#{namespace}::#{token}"
          when :class_method, :module_function
            "#{namespace}.#{token}"
          when :instance_method
            "#{namespace}##{token}"
          else
            namespace # or raise error
          end
        end

        # Resolves a token on the wrapped object.
        # @param token [String]
        # @return [TokenClassification]
        # @raise [TokenNotResolvedError]
        def resolve(token)
          return self
        end

        # Returns possible completions for the wrapped object, matching the prefix.
        # @param prefix [String]
        # @return [Array<TokenClassification>]
        def get_completions(prefix)
          return []
        end

      end

      # We have a reference to the actual object.
      # The next token can be looked up by reflection.
      class TokenClassificationByObject < TokenClassification

        def initialize(token, type, namespace, returned_object)
          super(token, type, namespace)
          @returned_object = returned_object # object identified or returned by the token
        end

        def object
          return @returned_object
        end

        def resolve(token)
          # Module/Class with constant
          if @returned_object.is_a?(Module) && @returned_object.constants.include?(token.to_sym)
            return_value = @returned_object.const_get(token.to_sym)
            @token = token
            @type = (return_value.is_a?(Class)) ? :class : (return_value.is_a?(Module)) ? :module : :constant
            @namespace = @returned_object.name
            @returned_object = @returned_object.const_get(token)
            return self
          # Class constructor method
          elsif @returned_object.is_a?(Class) && token == 'new'
            namespace = @returned_object.name
            returned_class = @returned_object
            return TokenClassificationByClass.new(token, :class_method, namespace, returned_class, true)
          # Module/Class method, instance method
          elsif @returned_object.respond_to?(token)
            returned_is_instance = !@returned_object.is_a?(Module)
            returned_namespace = (returned_is_instance) ? @returned_object.class.name : @returned_object.name
            return TokenClassificationByDoc.new(@token, @type, @namespace, returned_namespace, returned_is_instance).resolve(token)
          else
            raise TokenNotResolvedError.new("Failed to resolve token '#{token}' for object #{@returned_object.inspect[0..100]}")
          end
        end

        def get_completions(prefix)
          prefix_regexp = Regexp.new('^' + prefix)
          completions = []
          is_instance = !@returned_object.is_a?(Module)
          if is_instance
            completions.concat(@returned_object.methods.grep(prefix_regexp).map{ |method|
              TokenClassification.new(method, :instance_method, @returned_object.class.name)
            })
          else
            completions.concat(@returned_object.constants.grep(prefix_regexp).map{ |constant|
              return_value = @returned_object.const_get(constant)
              type = (return_value.is_a?(Class)) ? :class : (return_value.is_a?(Module)) ? :module : :constant
              TokenClassification.new(constant, type, @returned_object.name)
            })
            type = (@returned_object.is_a?(Class)) ? :class_method : :module_function
            completions.concat(@returned_object.methods.grep(prefix_regexp).map{ |method|
              TokenClassification.new(method, type, @returned_object.name)
            })
          end
          return completions
        end

      end

      # The object's class is known, but we don't have a reference to an instance.
      # The next token can be looked up by reflection.
      class TokenClassificationByClass < TokenClassification

        def initialize(token, type, namespace, returned_class, returned_is_instance=true)
          super(token, type, namespace)
          @returned_class = returned_class # Class of the object identified or returned by the token.
          @is_instance = returned_is_instance # Whether the object identified or returned by the token is an instance
        end

        def resolve(token)
          if @is_instance == false
            # Module/Class with constant
            if @returned_class.constants.include?(token.to_sym)
              return_value = @returned_class.const_get(token)
              if return_value.is_a?(Module)
                @token = token
                @type = return_value.is_a?(Class) ? :class : :module
                @namespace = @returned_class.name
                @returned_class = return_value
                return self
              else # return_value is an object
                return TokenClassificationByObject(token, :constant, @returned_class.name, return_value)
              end
            # Class constructor method
            elsif token == 'new'
              @token = token
              @type = :class_method
              @namespace = @returned_class.name
              # @returned_class stays the same
              @is_instance = true
              return self
            # Module/Class method
            else
              returned_namespace = @returned_class.name
              return TokenClassificationByDoc.new(@token, @type, @namespace, returned_namespace, @is_instance).resolve(token)
            end
          # instance method
          elsif @returned_class.instance_methods.include?(token.to_sym)
            returned_namespace = @returned_class.name
            return TokenClassificationByDoc.new(@token, :instance_method, @namespace, returned_namespace, @is_instance).resolve(token)
          else
            raise TokenNotResolvedError.new("Failed to resolve token '#{token}' for #{@is_instance ? 'an instance of' : ''} class #{@returned_class.name}")
          end
        end

        def get_completions(prefix)
          prefix_regexp = Regexp.new('^' + prefix)
          completions = []
          if @is_instance
            completions.concat(@returned_class.instance_methods.grep(prefix_regexp).map{ |method|
              TokenClassification.new(method, :instance_method, @returned_class.name)
            })
          else
            completions.concat(@returned_class.constants.grep(prefix_regexp).map{ |constant|
              return_value = @returned_object.const_get(constant)
              type = (return_value.is_a?(Class)) ? :class : (return_value.is_a?(Module)) ? :module : :constant
              TokenClassification.new(constant, type, @returned_class.name)
            })
            type = (@returned_class.is_a?(Class)) ? :class_method : :module_function
            completions.concat(@returned_class.methods.grep(prefix_regexp).map{ |method|
              TokenClassification.new(method, type, @returned_class.name)
            })
          end
          return completions
        end

      end

      # A docstring of the class is known.
      # The next token can only be looked up in documentation (e.g. type of return value from methods).
      class TokenClassificationByDoc < TokenClassification

        def initialize(token, type, namespace, returned_namespace, returned_is_instance=true)
          super(token, type, namespace)
          @returned_namespace = returned_namespace # path of object identified or returned by the token
          @is_instance = returned_is_instance # Whether the object identified or returned by the token is an instance
        end

        def resolve(token)
          # Module/Class with constant
          if @is_instance == false &&
              ( doc_info = DocProvider.get_info_for_docpath(docpath + '::' + token) )
            @token = token
            @type = doc_info[type] # :constant, :class, :module
            @namespace = doc_info[:path] # Path including the constant
            @returned_namespace = docpath # TokenClassification#docpath, new path after changing other attributes
            @is_instance = false # assume the constant is a Class or Module
            return self
          # Class constructor method
          elsif @is_instance == false && token == 'new'
            @token = token
            @type = :class_method
            @namespace = @returned_namespace
            # @returned_namespace stays the same (constructor returns an instance of the class)
            @is_instance = true
            return self
          else
            # method
            path = @returned_namespace + ((@is_instance) ? '#' : '.') + token
            doc_info = DocProvider.get_info_for_docpath(path)
            if doc_info && doc_info[:return] && doc_info[:return].first
              returned_types = Autocompleter.parse_return_types(doc_info[:return].first)
              returned_type = returned_types.first # TODO: consider all
              @token = token
              @type = (@is_instance) ? :instance_method : :class_method
              @namespace = @returned_namespace
              @returned_namespace = returned_type
              @is_instance = true # assume the method returns not a Class
            else
              unless try_apply_common_knowledge(token)
                raise TokenNotResolvedError.new("Failed to resolve token '#{token}' for #{@is_instance ? 'an instance of' : ''} class #{@returned_namespace} through documentation")
              end
            end
          end
          # Try to resolve the returned type to a class in object space, which then allows introspection.
          begin
            return TokenClassificationByClass.new(@token, @type, @namespace, Autocompleter.resolve_module_path(@returned_namespace), @is_instance)
          rescue NameError
          end
          return self
        end

        def get_completions(prefix)
          prefix_regexp = Regexp.new('^' + prefix)
          completions = DocProvider.get_infos_for_docpath(@returned_namespace).select{ |doc_info|
            prefix_regexp =~ doc_info[:name]
          }.map{ |doc_info|
            TokenClassification.new(doc_info[:name], doc_info[:type], doc_info[:path].sub(/[\.\#][^\.\#]$/, ''))
          }
          return completions
        end

        def try_apply_common_knowledge(token)
          token = token.to_s
          if COMMON_KNOWLEDGE.include?(token)
            @token = token
            @type = :instance_method
            @namespace = @returned_namespace
            @returned_namespace = COMMON_KNOWLEDGE[token]
            @is_instance = true # Currently in common knowledge we only have instance methods that return instances.
            return true
          end
          return false
        end

        COMMON_KNOWLEDGE ||= {
          'class' => 'Class',
          'count' => 'Integer',
          'inspect' => 'String',
          'length' => 'Integer',
          'map' => 'Enumerable',
          'select' => 'Enumerable',
          'find_all' => 'Enumerable',
          'size' => 'Integer',
          'to_a' => 'Array',
          'to_f' => 'Float',
          'to_i' => 'Integer',
          'to_s' => 'String'
        }

      end

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
