module AE

  module ConsolePlugin

    require(File.join(PATH, 'features', 'docprovider.rb'))

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

      attr_reader :token, :type, :namespace

      def initialize(token, type, namespace)
        @token = token
        @type = type           # type of the token
        @namespace = namespace # path of object/class before the token, leading to the token
      end

      # Returns the class path and token.
      # @return [String]
      def docpath
        return case type.to_sym
        when :constant, :module, :class
          (namespace.empty?) ? token.to_s : "#{namespace}::#{token}"
        when :class_method, :module_function
          "#{namespace}.#{token}"
        when :instance_method
          "#{namespace}##{token}"
        else
          namespace.to_s # or raise error
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

      # These methods needed for testing equality and uniq:

      def eql?(other)
        return other.is_a?(TokenClassification) &&
               @token == other.token &&
               @type == other.type &&
               @namespace = other.namespace
      end

      def hash
        return @token.hash + @type.hash + @namespace.hash
      end

    end

    # This is a wrapper around a set of multiple classifications under 
    # consideration for the same token.
    class MultipleTokenClassification < TokenClassification

      def initialize(classifications)
        raise ArgumentError.new('Argument must be an array') unless classifications.is_a?(Array)
        raise ArgumentError.new('Argument cannot be an empty array') if classifications.empty?
        raise ArgumentError.new('All given classifications must be for the same token') unless classifications.map(&:token).uniq.length == 1
        # If the argument contains MultipleTokenClassifications, decompose them.
        classifications.map!{ |item|
          (item.is_a?(MultipleTokenClassification)) ? item.classifications : item
        }.flatten!
        classifications.uniq!
        # Code that only supports a unique namespace/type or type will receive only the first one!
        super(classifications.first.token, classifications.first.type, classifications.first.namespace)
        @classifications = classifications
      end

      attr_reader :classifications

      def resolve(token)
        results = []
        @classifications.each{ |classification|
          begin
            result = classification.resolve(token)
            if result.is_a?(MultipleTokenClassification)
              results.concat(result.classifications)
            else
              results << result
            end
          rescue TokenNotResolvedError
            next
          end
        }
        if classifications.empty?
          raise TokenNotResolvedError.new("Failed to resolve token '#{token}' for multiple classications #{self.inspect[0..100]}")
        elsif classifications.length == 1
          return classifications.first
        else
          return MultipleTokenClassification.new(results) # This ensures result does not include duplicates
        end
      end

      def get_completions(prefix)
        results = []
        @classifications.each{ |classification|
          results.concat(classification.get_completions(prefix))
        }
        return results
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
          returned_class = (returned_is_instance) ? @returned_object.class : @returned_object
          # Take the method from the correct module if it comes from an included module.
          returned_class.included_modules.each{ |modul|
            if modul.instance_methods.include?(token.to_sym)
              returned_class = modul
              break
            end
          }
          returned_namespace = returned_class.name
          return TokenClassificationByDoc.new(@token, @type, @namespace, returned_namespace, returned_is_instance).resolve(token)
        else
          raise TokenNotResolvedError.new("Failed to resolve token '#{token}' for object #{@returned_object.inspect[0..100]}")
        end
      end

      def get_completions(prefix)
        prefix_regexp = Regexp.new('^' + prefix)
        completions = []
        returned_is_instance = !@returned_object.is_a?(Module)
        if returned_is_instance
          # Take the method from the correct module if it comes from an included module.
          @returned_object.class.included_modules.each{ |modul|
            completions.concat(modul.instance_methods.grep(prefix_regexp).map{ |method|
              TokenClassification.new(method, :instance_method, modul.name)
            })
          }
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
          # Take the method from the correct module if it comes from an included module.
          @returned_class.included_modules.each{ |modul|
            if modul.instance_methods.include?(token.to_sym)
              @returned_class = modul
              break
            end
          }
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
          # Take the method from the correct module if it comes from an included module.
          @returned_class.included_modules.each{ |modul|
            completions.concat(modul.instance_methods.grep(prefix_regexp).map{ |method|
              TokenClassification.new(method, :instance_method, modul.name)
            })
          }
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
          @namespace = doc_info[:path] # Path including the constant, same as `doc_info[:namespace]+'::'+doc_info[:name]
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
          if doc_info && doc_info[:return]
            returned_types = DocProvider.extract_return_types(doc_info)
            classifications = returned_types.map{ |returned_type|
              type = (@is_instance) ? :instance_method : :class_method
              begin
                # Try to resolve the returned type to a class in object space, which then allows introspection.
                returned_class = resolve_module_path(returned_type)
                TokenClassificationByClass.new(token, type, @returned_namespace, returned_class, true) # is_instance = true, assume the method returns not a Class
              rescue NameError
                TokenClassificationByDoc.new(token, type, @returned_namespace, returned_type, true) # is_instance = true, assume the method returns not a Class
              end
            }
            if classifications.length == 1
              return classifications.first
            else
              return MultipleTokenClassification.new(classifications)
            end
          else
            if try_apply_common_knowledge(token)
              return self
            else
              raise TokenNotResolvedError.new("Failed to resolve token '#{token}' for #{@is_instance ? 'an instance of' : ''} class #{@returned_namespace} through documentation")
            end
          end
        end
      end

      def get_completions(prefix)
        prefix_regexp = Regexp.new('^' + prefix)
        completions = DocProvider.get_infos_for_docpath_prefix(@returned_namespace).select{ |doc_info|
          prefix_regexp =~ doc_info[:name]
        }.map{ |doc_info|
          TokenClassification.new(doc_info[:name], doc_info[:type], doc_info[:namespace])
        }
        return completions
      end

      private

      # @param path [String]
      # @raise [NameError]
      # @private
      def resolve_module_path(path)
        tokens = path.split('::')
        return tokens.reduce(::Object){ |modul, token| modul.const_get(token) }
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

  end # module ConsolePlugin

end # module AE
