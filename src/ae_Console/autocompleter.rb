# requires AE::Console.unnested_eval in 'console.rb'
# requires DocProvider.get_type_paths in 'docprovider.rb'


module AE


  class Console


    # This module suggests completions from the live ObjectSpace using Ruby's inflection methods.
    # This way we get highly relevant suggestions that not only match alphabetically to the input,
    # but also to what is valid in the current context.
    module Autocompleter


      class << self


        unless defined?(self::CONSTANT)
          CONSTANT = /^[A-Z]/
          GLOBAL_VARIABLE = /^\$/
          INSTANCE_VARIABLE = /^@[^@]/
          CLASS_VARIABLE = /^@@/
          METHOD = /^[^\d;,:#`'"=\.\{\}\(\)\]\$\?\\]/
          SCOPE_OPERATOR = :'::'
          METHOD_OPERATOR = :'.'
        end


        # Get all possible completions for a prefix depending on its preceding tokens.
        # This method analyzes which object in Ruby ObjectSpace the prefix relates to and which methods/constants/etc.
        # are available in the current context.
        # @param [String]        prefix      An incomplete token.
        # @param [Array<String>] token_list  The list of preceding tokens.
        # @param [Object]        context     The root object in the context of which code is evaluated.
        # @return [Array<Hash>]              completions with keys:
        #
        #     :caption => [String]  The display text for the completion, we use here the Ruby class path notation.
        #     :value   => [String]  The completed token for the prefix.
        #     :score   => [Numeric]
        #     :meta    => [Symbol]  Specifies the type, one of: :global_variable, :class_variable, :instance_variable,
        #                           :constant, :class_method, :instance_method
        # @raise [AutocompleterException]    If the given token list cannot be resolved due to unexpected tokens or operators.
        def complete(prefix, token_list, context=Object, binding=TOPLEVEL_BINDING)
          if token_list.empty?
            get_available_tokens_at_start(prefix, context, binding)
          else
            if prefix.to_sym == SCOPE_OPERATOR || prefix.to_sym == METHOD_OPERATOR
              last_operator = prefix.to_sym
              prefix = ''
            else
              last_operator = token_list.pop.to_sym
            end
            object = resolve_object(token_list, context, binding)
            case last_operator
            when METHOD_OPERATOR
              result = get_available_tokens_after_method_operator(prefix, object)
            when SCOPE_OPERATOR
              result = get_available_tokens_after_scope_operator(prefix, object)
            else
              raise NoObjectMatchException.new('Token before prefix is not a valid operator'+" `#{token_list}`, `#{last_operator}`, `#{prefix}`")
              # result = get_available_tokens_at_start(prefix, context, binding)
            end
            return result
          end
        end


        # Try to resolve a token list to an object and get the class path.
        # @param [Array<String>] token_list  The list of tokens.
        # @param [Object]        context     The root object in the context of which code is evaluated.
        # @return [Array(String,Symbol)]     A string of the class path, and a symbol specifying the type.
        #                                    One of: :class, :module, :constant, :class_method, :instance_method,
        # @raise [AutocompleterException]    If the given token list cannot be resolved due to unexpected tokens or operators.
        def classify_token(token_list, context, binding=TOPLEVEL_BINDING)
          raise NoObjectMatchException.new('Token list empty') if token_list.empty?
          path = nil
          type = nil
          item = token_list.pop.to_sym
          item = token_list.pop.to_sym if item == SCOPE_OPERATOR || item == METHOD_OPERATOR
          object = resolve_object(token_list, context, binding)
          if object.is_a?(Module) # or Class
            path = object.name
            if object.constants.include?(item)
              path += "::#{item}"
              type = case object.const_get(item)
              when Class
                :class
              when Module
                :module
              else
                :constant
              end
            elsif object.methods.include?(item)
              path += ".#{item}"
              type = :class_method
            else
              raise NoObjectMatchException.new("No class path found for #{item}")
            end
          elsif object == context # and instance
            path = ''
            _object = object.class
            if _object.constants.include?(item)
              path += "#{item}"
              type = case _object.const_get(item)
              when Class
                :class
              when Module
                :module
              else
                :constant
              end
            elsif (object.methods.concat(object.private_methods)).include?(item)
              path += "##{item}"
              type = :instance_method
            else
              raise NoObjectMatchException.new("No class path found for #{item}")
            end
          else # instance
            path = object.class.name
            if object.methods.include?(item)
              path += "##{item}"
              type = :instance_method
            else
              raise NoObjectMatchException.new("No class path found for #{item}")
            end
          end
          return [path, type]
        end


        # Try to resolve a token list to an object and get the class path.
        # @param [Array<String>] token_list  The list of tokens.
        # @param [Object]        context     The root object in the context of which code is evaluated.
        # @return [Object]                   The object described by the tokens.
        # @raise [AutocompleterException]    If the given token list cannot be resolved due to unexpected tokens or operators.
        # @note The returned object does not allow to derive its class path. Methods will become unbound methods.
        def resolve_object(token_list, context, binding=TOPLEVEL_BINDING)
          return context if token_list.empty?
          token = token_list.shift
          object = get_start_object(token, context, binding)
          unless token_list.empty?
            object = get_by_object(token_list, object)
          end
          return object
        end


        private


        def resolve_class_path(path)
          path, item = path.split(/[\.#]/)
          modul = path.reduce(::Object){ |modul, constant| modul.const_get(constant) }
          if item
            return modul.method(item)          if path[/\.\w+$/]
            return modul.instance_method(item) if path[/#\w+$/]
            raise NoObjectMatchException
          end
          return modul
        end


        def get_start_object(token, context, binding)
          t = token.to_sym
          case t
          when SCOPE_OPERATOR
            return context
          when CONSTANT
            _context = (context.is_a?(Module)) ? context : context.class
            raise NoObjectMatchException.new("No constant found for `#{t}`") unless _context.constants.include?(t)
            return _context.const_get(t)
          when GLOBAL_VARIABLE
            raise NoObjectMatchException.new("No global variable found for `#{t}`") unless Kernel.global_variables.include?(t)
            return eval(t, TOPLEVEL_BINDING)
          when INSTANCE_VARIABLE
            raise NoObjectMatchException.new("No instance variable found for `#{t}`") unless context.instance_variable_defined?(t)
            return context.instance_variable_defined?(t)
          when CLASS_VARIABLE
            raise NoObjectMatchException.new("No class variable found for `#{t}`") unless context.instance_variable_defined?(t)
            return context.instance_variable_defined?(t)
          else # Method or local variable
            if (AE::Console).unnested_eval('local_variables', binding).include?(t)
              return (AE::Console).unnested_eval(t.to_s, binding)
            elsif context.methods.include?(t) || Kernel.methods.include?(t)
              raise TypeInferenceException.new("Unresolvable because `#{t}` is a method → Get type from docs")
            else
              raise NoObjectMatchException.new("No object found for `#{t}`")
            end
          end
        end


        def get_by_object(token_list, object)
          token = token_list.shift
          t0 = token.to_sym
          # Only operator, then empty.
          if token_list.empty?
            if t0 == SCOPE_OPERATOR || t0 == METHOD_OPERATOR
              return object
            else
              raise NoObjectMatchException.new("Last token must be operator but was `#{t0}`")
            end
          # Module::… or Class::…
          elsif object.is_a?(Module) && t0 == SCOPE_OPERATOR
            token = token_list.shift
            t1 = token.to_sym
            # Module::CONSTANT or Class::CONSTANT
            if t1[CONSTANT] && object.constants.include?(t1)
              object = object.const_get(t1)
            # Module.module_method or Class.class_method
            elsif object.methods.include?(t1)
              #object = object.method(token)
              raise TypeInferenceException.new("Unresolvable because `#{t1}` is a method → Get type from docs")
            else
              raise NoObjectMatchException.new("No constant or class method found for `#{t1}`")
            end
          # Any instance.…
          elsif t0 == METHOD_OPERATOR # and object is Module, Class or instance
            token  = token_list.shift
            t1 = token.to_sym
            # Module.module_method, Class.class_method, instance.instance_method
            raise NoObjectMatchException.new("No method found for `#{t1}`") unless object.methods.include?(t1)
            #object = object.method(token)
            raise TypeInferenceException.new("Unresolvable because `#{t1}` is a method → Get type from docs")
            modul = (object.is_a?(Module)) ? object : object.class
            path = "#{modul.name}.#{t1}"
            return_types = DocProvider.get_type_paths(path)
            return_types.map{ |return_type|
              resolve_class_path(return_type)
            }
            # TODO: Get type from docs
          else
            raise NoObjectMatchException.new("Scope or method operator expected for `#{t0}`")
          end
          # End the recursion or continue.
          if token_list.empty?
            return object
          else
            return get_by_object(token_list, object)
          end
        end


        # TODO: distinguish whether context is module or instance:
        # module: global, class_var, local, methods, (instance_methods)
        # instance: global, instance_var, local, methods
        def get_available_tokens_at_start(prefix, context, binding)
          result = []
          _context = (context.is_a?(Module)) ? context : context.class
          #result.concat(get_available_tokens_after_scope_operator(prefix, _context))
          result.concat(get_available_constants(prefix, _context))
          result.concat(get_available_tokens_after_method_operator(prefix, context))
          case prefix
          when GLOBAL_VARIABLE
            globals = Kernel.global_variables.select{ |global| global.to_s.index(prefix) == 0 }
            result.concat(globals.map{ |global|
              {
                  :caption => global,
                  :value => global,
                  :score => 1000,
                  :meta => 'global variable'
              }
            })
          when INSTANCE_VARIABLE
            instance_variables = context.instance_variables.find_all{ |variable| variable.to_s.index(prefix) == 0 }
            result.concat(instance_variables.map{ |instance_variable|
              {
                  :caption => ((context == TOPLEVEL_OBJECT) ? '' : "#{context.class.name}.") + "#{instance_variable}",
                  :value => instance_variable,
                  :score => 1000,
                  :meta => 'instance variable'
              }
            })
          when CLASS_VARIABLE
            class_variables = _context.class_variables.find_all{ |variable| variable.to_s.index(prefix) == 0 }
            result.concat(class_variables.map{ |class_variable|
              {
                  :caption => ((context == TOPLEVEL_OBJECT) ? '' : "#{context.class.name}::") + "#{class_variable}",
                  :value => class_variable,
                  :score => 1000,
                  :meta => 'class variable'
              }
            })
          else # Local variable
            variables = (AE::Console).unnested_eval('local_variables', binding).find_all{ |variable|
              variable.to_s.index(prefix) == 0 &&
              variable != :ae_console_exception
            }
            result.concat(variables.map{ |variable|
              {
                  :caption => "#{variable}", # TODO: notation of local variables?
                  :value => variable,
                  :score => 1000,
                  :meta => 'local variable'
              }
            })
            # Local methods
            instance_methods = (context.methods.concat(context.private_methods)).find_all{ |method|
              method.to_s.index(prefix) == 0
            }
            result.concat(instance_methods.map{ |method|
              {
                  :caption => "##{method}",
                  :value => method,
                  :score => 1000,
                  :meta => 'instance method'
              }
            })
          end
          return result
        end


        def get_available_tokens_after_method_operator(prefix, object)
          result = []
          if prefix[METHOD] || prefix.empty?
            # Module method or class method
            if object.is_a?(Module) # or Class
              class_methods = object.methods.find_all{ |class_method| class_method.to_s.index(prefix) == 0 }
              result.concat(class_methods.map{ |class_method|
                {
                    :caption => "#{object.name}.#{class_method}",
                    :value => class_method,
                    :score => 1000,
                    :meta => ':class method'
                }
              })
            else # Instance method
              instance_methods = object.methods.find_all{ |instance_method| instance_method.to_s.index(prefix) == 0 }
              result.concat(instance_methods.map{ |instance_method|
                {
                    :caption => "#{object.class.name}##{instance_method}",
                    :value => instance_method,
                    :score => 1000,
                    :meta => 'instance method'
                }
              })
            end
          end
          return result
        end


        def get_available_tokens_after_scope_operator(prefix, modul)
          result = []
          return result unless modul.is_a?(Module)
          result.concat(get_available_constants(prefix, modul))
          if prefix[METHOD] || prefix.empty?
            class_methods = modul.methods.find_all{ |class_method| class_method.to_s.index(prefix) == 0 }
            result.concat(class_methods.map{ |class_method|
              {
                  :caption => "#{modul.name}.#{class_method}",
                  :value => class_method,
                  :score => 1000,
                  :meta => 'class method'
              }
            })
          end
          return result
        end


        def get_available_constants(prefix, modul)
          result = []
          return result unless modul.is_a?(Module)
          # Lookup through all outer modules.
          get_nesting(modul).each{ |_modul|
            constants = _modul.constants.find_all{ |constant| constant.to_s.index(prefix) == 0 }
            result.concat(constants.map{ |constant|
              {
                  :caption => (modul == ::Object) ? constant : "#{modul.name}::#{constant}",
                  :value => constant,
                  :score => 1000,
                  :meta => 'constant'
              }
            })
          }
          return result
        end


        def get_nesting(modul)
          nesting = modul.name.split('::').reduce([Object]){ |_nesting, constant|
            _nesting << _nesting.last.const_get(constant)
          }
          nesting.shift # Object
          return nesting.reverse
        end


      end # class << self


      class AutocompleterException < Exception; end
      class NoObjectMatchException < AutocompleterException; end
      class TypeInferenceException < AutocompleterException; end


    end # module Autocompleter


  end


end
