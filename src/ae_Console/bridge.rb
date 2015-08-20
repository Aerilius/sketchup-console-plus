=begin
Library to facilitate WebDialog communication with SketchUp's Ruby environment.

@module  Bridge
@version 2.0.0
@date    2015-08-08
@author  Andreas Eisenbarth
@license MIT License (MIT)

The callback mechanism provided by SketchUp with a custom protocol handler `skp:` has several deficiencies:
 * Inproper Unicode support; looses properly escaped calls containing '; drops repeated properly escaped backslashes.
 * Maximum url length in the Windows version of SketchUp is 2083. (https://support.microsoft.com/en-us/kb/208427)
 * Asynchronous on OSX (it doesn't wait for SketchUp to receive a previous call) and can loose quickly sent calls.
 * Supports only one string parameter that must be escaped.
  (as documented here: https://github.com/thomthom/sketchup-webdialogs-the-lost-manual)

This Bridge provides an intuitive and safe communication with any amount of arguments of any JSON-compatible type and
a way to access the return value. It implements a message queue to ensure communication is sequential. It is based on
Promises which allow easy asynchronous and delayed callback paths for both success and failure.

@example Simple call
# On the Ruby side:
  @bridge = Bridge.new(webdialog)
  @bridge.on("add_image") { |dialog, image_path, point, width, height|
    @entities.add_image(image_path, point, width.to_l, height.to_l)
  }
# On the JavaScript side:
  Bridge.call('add_image', 'http://www.photos.com/image/9895.jpg', [10, 10, 0], '2.5m', '1.8m');

@example Log output to the Ruby Console
  Bridge.puts('Swiss "grüezi" is pronounced [ˈɡryə̯tsiː] and means "您好！" in Chinese.');

@example Log an error to the Ruby Console
  try {
    document.produceError();
  } catch (error) {
    Bridge.error(error);
  }

@example Usage with promises
# On the Ruby side:
  @bridge.on("do_calculation") { |promise, length, width|
    if validate(length) && validate(width)
      result = calculate(length)
      promise.resolve(result)
    else
      promise.reject("The input is not valid.")
    end
  }
# On the JavaScript side:
  var promise = Bridge.get('do_calculation', length, width)
  promise.then(function(result){
    $('#resultField').text(result);
  }, function(failureReason){
    $('#inputField1').addClass('invalid');
    $('#inputField2').addClass('invalid');
    alert(failureReason);
  });

=end
require(File.join(File.dirname(__FILE__), 'promise.rb'))
# Optionally requires 'json.rb'
# Requires modules Sketchup, UI


module AE


  class Console


    class Bridge


      # Add the bridge to an existing UI::WebDialog.
      # This can be used for convenience and will define the bridge's methods
      # on the dialog and delegate them to the bridge.
      # @param  [UI::WebDialog] dialog
      # @return [UI::WebDialog] The decorated dialog
      def self.decorate(dialog)
        bridge = self.new(dialog)
        dialog.instance_variable_set(:@bridge, bridge)

        def dialog.bridge
          return @bridge
        end

        def dialog.on(name, callback=nil, &callback_)
          @bridge.on(name, callback, &callback_)
          return self
        end

        def dialog.once(name, callback=nil, &callback_)
          @bridge.once(name, callback, &callback_)
          return self
        end

        def dialog.off(name)
          @bridge.off(name)
          return self
        end

        def dialog.call(function, *arguments, &callback)
          @bridge.call(function, *arguments, &callback)
        end

        def dialog.get(function, *arguments)
          return @bridge.get(function, *arguments)
        end

        def dialog.get_sync(function, *arguments)
          return @bridge.get_sync(function, *arguments)
        end

        return dialog
      end


      # The name space to avoid clashes with internal callback handlers or other action_callbacks.
      # It must match the module path of the corresponding JavaScript implementation.
      NAMESPACE = 'Bridge'

      # The url which responds to requests.
      URL_RECEIVE = "#{NAMESPACE}.receive"

      # Names that are used internally and not allowed to be used as callback handler names.
      RESERVED_NAMES = []

      # Workaround for SketchUp's bug that Procs are never released for garbage collection and may prevent webdialogs
      # or ruby objects referenced in the to be garbage collected. This proc is re-used and delegates to the actual
      # proc of each action_callback.
      CALLBACK_WRAPPER = Proc.new { |dialog, params|
        ObjectSpace.each_object(Bridge){ |bridge|
          break bridge.__callback_wrapper__(dialog, params) if bridge.dialog == dialog
        }
      }
      private_constant :CALLBACK_WRAPPER if methods.include?(:private_constant)


      attr_reader :dialog


      # Add a callback handler. Overwrites an existing callback handler of the same name.
      # @param  [String]              name      The name under which the callback can be called from the dialog.
      # @param  [Proc,UnboundMethod]  callback  A method or proc for the callback, if no yield block given.
      # @yield  A callback to be called from the dialog to execute Ruby code.
      # @yieldparam [Message]         dialog    An object referencing the dialog, enhanced with methods
      #                                         {Message#resolve} and {Message#resolve} to return results to the dialog.
      # @yieldparam [Array<Object>]   arguments The JSON-compatible arguments passed from the dialog.
      # @return [self]
      def on(name, callback=nil, &callback_)
        raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
        raise(ArgumentError, "Argument `name` can not be `#{name}`.") if RESERVED_NAMES.include?(name)
        raise(ArgumentError, 'Argument `callback` must be a Proc or UnboundMethod.') unless block_given? || callback.respond_to?(:call)
        callback      ||= callback_
        @handlers[name] = callback
        return self
      end


      # Add a callback handler to be called only once. Overwrites an existing callback handler of the same name.
      # @param  [String]              name      The name under which the callback can be called from the dialog.
      # @param  [Proc,UnboundMethod]  callback  A method or proc for the callback, if no yield block given.
      # @yield  A callback to be called from the dialog to execute Ruby code.
      # @yieldparam [Message]         dialog    An object referencing the dialog, enhanced with methods
      #                                         {Message#resolve} and {Message#resolve} to return results to the dialog.
      # @yieldparam [Array<Object>]   arguments The JSON-compatible arguments passed from the dialog.
      # @return [self]
      # TODO: nice, but only if not-found handler names don't raise an error.
      # TODO: Maybe allow many handlers for the same name?
      def once(name, callback=nil, &callback_)
        raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
        raise(ArgumentError, "Argument `name` can not be `#{name}`.") if RESERVED_NAMES.include?(name)
        raise(ArgumentError, 'Argument `callback` must be a Proc or UnboundMethod.') unless block_given? || callback.respond_to?(:call)
        callback      ||= callback_
        @handlers[name] = Proc.new { |*arguments|
          @handlers.delete(name)
          callback.call(*arguments)
        }
        return self
      end


      # Remove a callback handler.
      # @param  [String] name
      # @return [self]
      def off(name)
        raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
        @handlers.delete(name)
        return self
      end


      # Call a JavaScript function with JSON arguments in the webdialog.
      # @param [String] name       name of a public JavaScript function
      # @param [Object] arguments  array of JSON-compatible objects or Callables (Proc, UnboundMethod)
      # TODO: error catching!
      def call(name, *arguments)
        raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
        arguments = self.class.serialize(arguments)[1...-1]
        arguments = 'undefined' if arguments.nil? || arguments.empty?
        @dialog.execute_script("#{name}(#{arguments})")
      end


      # Call a JavaScript function with JSON arguments in the webdialog and get the
      # return value in a promise.
      # @param  [String] name       name of a public JavaScript function
      # @param  [Object] arguments  array of JSON-compatible objects
      # @return [Promise]
      # TODO: This uses the request handler, but is not async
      # The same could be done by just writing to the messageField and reading the value; Problem: collisions with pump?
      #   __passToRuby__(id, javascriptFunction()) creates a messagefield with unique id;
      #   then it can be read immediately with get_element_value; no promise needed.
      #   Needed: create unique id on ruby side, js method to set up (or re-use) messagefield; new RequestHandler();
      #   that creates message field and removes it when/before being garbage collected? __getSync__ ?
      # And still an async solution would be needed…
      def get(name, *arguments)
        raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
        arguments = self.class.serialize(arguments)[1...-1]
        arguments = 'undefined' if arguments.nil? || arguments.empty?
        return Promise.new { |resolve, reject|
          handler_name = create_unique_handler_name('resolve/reject')
          once(handler_name) { |dlg, success, arguments|
            if success
              resolve.call(*arguments)
            else
              reject.call(*arguments)
            end
          }
          @dialog.execute_script(
            <<-SCRIPT
            try{
                #{NAMESPACE}.call('#{handler_name}', true, #{name}(#{arguments}) );
            } catch (error) {
                #{NAMESPACE}.call('#{handler_name}', false, error.name + ': ' + error.message);
                #{NAMESPACE}.error(error);
            }
            SCRIPT
          )
        }
      end
      def get_sync(name, *arguments)
        raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
        arguments = self.class.serialize(arguments)[1...-1]
        arguments = 'undefined' if arguments.nil? || arguments.empty?
        success = @dialog.execute_script("#{NAMESPACE}.responseHandler( #{name}(#{arguments}) )");
        result = @dialog.get_element_value("#{NAMESPACE}.responseField")
        result = self.class.unserialize(result)
        return result
      end

=begin # TODO: test and remove:
      # Call a JavaScript function with JSON arguments in the webdialog.
      # @param  [String]   name       name of a public JavaScript function
      # @param  [Object]   arguments  array of JSON-compatible objects or Callables (Proc, UnboundMethod)
      # @return [Promise]
      def call(name, *arguments, &callback)
        arguments << callback if block_given?
        arguments = arguments.map { |arg|
          if arg.is_a?(Proc) || arg.is_a?(UnboundMethod)
            function_name = create_unique_handler_name("call")
            on(function_name) { |dlg, *arguments|
              arg.call(*arguments)
            }
            'function(){ ' <<
                '  var args = Array.prototype.slice.call(arguments);' <<
                "  args.unshift('#{function_name}');" <<
                "  #{NAMESPACE}.call.apply(window, args);" <<
                '}'
          else
            self.class.serialize([arg])[1...-1]
          end
        }.compact.join(', ')
        # @dialog.execute_script("#{name}(#{arguments})")
        @dialog.execute_script("try{ #{name}(#{arguments}) } catch(error) { #{NAMESPACE}.error(error) }")
      end


      # Call a JavaScript function with JSON arguments in the webdialog and get the
      # return value in a promise.
      # @param  [String]   name       name of a public JavaScript function
      # @param  [Object]   arguments  array of JSON-compatible objects
      # @return [Promise]
      def get(name, *arguments)
        arguments = self.class.serialize(arguments)
        arguments = 'undefined' if arguments.nil? || arguments.empty?
        return Promise.new { |resolve, reject|
          handler = create_unique_handler_name('resolve/reject')
          once(handler) { |dlg, success, arguments|
            if success
              resolve.call(*arguments)
            else
              reject.call(*arguments)
            end
          }
          # TODO: what if name(arguments) → Promise? then resolve this promise later!
          @dialog.execute_script("#{NAMESPACE}.__get__('#{handler}', #{name}, #{arguments})")
        }
      end
=end


      private


      # Create an instance of the Bridge and associate it with a dialog.
      # @param [UI::WebDialog] dialog
      def initialize(dialog)
        raise(ArgumentError, 'Argument `dialog` must be a UI::WebDialog.') unless dialog.is_a?(UI::WebDialog)
        @dialog         = dialog
        @handlers       = {}
        @handlers_show  = []
        @handlers_close = []

        # SketchUp does not release procs of WebDialogs. Because of that, we need to
        # make sure that the proc contains no reference to this instance. The proc
        # receives a reference to this dialog, so it can call the follow-up method #action_callback.
        @dialog.add_action_callback(URL_RECEIVE, &CALLBACK_WRAPPER)

        add_default_handlers
      end


      # Receives the raw messages from the WebDialog (AE.Bridge.call) and calls the individual callbacks.
      # @private Not for public use.
      # @param   [UI::WebDialog] dialog
      # @param   [String] params
      # @private
      def __callback_wrapper__(dialog, params)
        # Get message data from the hidden input element.
        value   = dialog.get_element_value("#{NAMESPACE}.requestField") # returns empty string if element not found
        request = self.class.unserialize(value)
        unless request.is_a?(Hash) &&
            request['id'].is_a?(Fixnum) &&
            request['name'].is_a?(String) &&
            request['arguments'].is_a?(Array)
          raise(ArgumentError, "Bridge received invalid data: \n#{value}")
        end
        id        = request['id']
        name      = request['name']
        arguments = request['arguments'] || []

        # Here we pass a wrapper around the dialog which preserves the message id to
        # identify the corresponding JavaScript callback.
        # This allows to run asynchronous code (external application etc.) and return
        # later the result to the JavaScript callback even if the dialog has continued
        # sending/receiving messages.
        response  = Message.new(dialog, id)
        # Get the callback.
        unless @handlers.include?(name)
          error = ArgumentError.new("No registered callback `#{name}` for #{dialog} found.")
          response.reject(error)
          raise(error)
        end
        handler = @handlers[name]
        begin
          handler.call(response, *arguments)
        rescue Exception => error
          response.reject(error)
          raise(error)
        end

      rescue Exception => e
        UI.messagebox(e.message+"\n"+e.backtrace.join("\n")) # TODO: remove
        AE::Console.error(e)
      ensure
        # Acknowledge that the message has been received and enable the bridge to send
        # the next message if available.
        dialog.execute_script("#{NAMESPACE}.__ack__()")
      end
      public :__callback_wrapper__


      # Add additional optional handlers for calls from JavaScript to Ruby.
      def add_default_handlers
        # Puts (for debugging)
        @handlers["#{NAMESPACE}.puts"] = Proc.new { |dialog, *arguments|
          puts(*arguments.map { |argument| argument.inspect })
        }
        RESERVED_NAMES << "#{NAMESPACE}.puts"

        # Error channel (for debugging)
        @handlers["#{NAMESPACE}.error"] = Proc.new { |dialog, type, message, backtrace|
          AE::Console.error(type + ': ' + message, {:language => 'javascript', :backtrace => backtrace})
        }
        RESERVED_NAMES << "#{NAMESPACE}.error"
      end


      # Create a string which has not yet been registered as callback handler, to avoid collisions.
      # @param  [String] string
      # @return [String]
      def create_unique_handler_name(string)
        begin
          int = (10000*rand).round
          handler_name = "#{NAMESPACE}.#{string}_#{int}"
        end while @handlers.include?(handler_name)
        return handler_name
      end


      # Class for message properties, combining the behavior of WebDialog and Promise.
      # SketchUp's WebDialog action callback procs receive as first argument a reference to the dialog.
      # To direct the return value of asynchronous callbacks to the corresponding JavaScript callback, we need to
      # remember the message id. We retain SketchUp's default behavior by delegating to the webdialog, while adding
      # the functionality of a promise.
      # @!parse include UI::WebDialog
      class Message < Promise


        # @param   [UI::WebDialog] dialog
        # @param   [Fixnum] id
        # @private
        def initialize(dialog, id)
          super()
          # Resolves a query from JavaScript and returns the result to it.
          on_resolve = Proc.new{ |*results|
            if results.first.respond_to?(:then)
              promise = results.first
              promise.then { |*results|
                resolve(*results)
              }
              promise.catch { |reason|
                reject(reason)
              }
            else
              arguments = Bridge.serialize(results)[1...-1]
              arguments = 'undefined' if arguments.nil? || arguments.empty?
              @dialog.execute_script("#{NAMESPACE}.__resolve__(#{@id}, #{arguments})")
            end
          }
          # Rejects a query from JavaScript and and give the reason/error message.
          on_reject = Proc.new{ |reason|
            #raise(ArgumentError, 'Argument `reason` must be an Exception or String.') unless reason.is_a?(Exception) || reason.is_a?(String)
            if reason.is_a?(Exception)
              error_class = case Exception
              when NameError then
                'ReferenceError'
              when SyntaxError then
                'SyntaxError'
              when TypeError then
                'TypeError'
              when ArgumentError then
                'TypeError'
              else # any Exception
                'Error'
              end
              reason = "new #{error_class}(#{reason.message.inspect})"
            elsif reason.is_a?(String)
              reason = reason.inspect
            else
              reason = Bridge.serialize(reason)
            end
            @dialog.execute_script("#{NAMESPACE}.__reject__(#{@id}, #{reason})")
          }
          # Register these two handlers.
          @handlers << Handler.new(on_resolve, on_reject, nil, nil)
          @dialog = dialog
          @id     = id
        end

        alias_method :return, :resolve

        # Delegate other method calls to the dialog.
        # @see UI::WebDialog
        def method_missing(method_name, *arguments, &block)
          return @dialog.__send__(method_name, *arguments, &block)
        end

      
      end # class Message


      # For serializing objects, we choose JSON.
      # If available and compatible, we prefer JSON from the standard libraries.
      if Sketchup.version.to_i >= 14
        begin
          # `Sketchup::require "json"` raises no error, but displays in the load errors popup.
          load 'json.rb' unless defined?(JSON)
          raise unless JSON::VERSION_MAJOR >= 1 && JSON::VERSION_MINOR >= 6 # support of option :quirks_mode


          # Serializes an object.
          # @param [Object] object
          # @return [String]
          # @private
          def self.serialize(object)
            # quirk_mode generates JSON from objects other than Hash and Array.
            # Attention! JSON in SketchUp's Ruby 2.0 standard lib does not fully implement quirk_mode.
            # return JSON.generate(object, {:quirk_mode => true})
            return JSON.generate([object])[1...-1]
          end


          # Unserializes the string representation of a serilized object.
          # @param [String] string
          # @return [Object]
          # @private
          def self.unserialize(string)
            # Attention! JSON in SketchUp's Ruby 2.0 standard lib does not fully implement quirk_mode.
            # return JSON.parse(string, {:quirk_mode => true})
            return JSON.parse("[#{string}]")[0]
          end


        rescue LoadError
          # Fallback JSON implementation.


          # @private
          def self.serialize(object)
            # Split at every even number of unescaped quotes. This gives either strings
            # or what is between strings.
            json_string = object.inspect.split(/"(?:\\"|[^"])*"/).
                map { |string|
              next string if string[0..0] == '"' # is a string in quotes
              # If it's not a string then replace : and null
              string.gsub(/=>/, ':').
                  gsub(/\bnil\b/, 'null')
            }.
                join('')
            return json_string
          end


          # @private
          def self.unserialize(string)
            # Split at every even number of unescaped quotes. This gives either strings
            # or what is between strings.
            # ruby_string = json_string.split(/(\"(?:.*?[^\\])*?\")/).
            # The outer capturing braces are important for that ruby keeps the separator patterns in the returned array.
            ruby_string = string.split(/("(?:\\"|[^"])*")/).
                map{ |s|
              # It is a string in quotes.
              if s[0..0] == '"'
                # Convert escaped unicode characters because eval won't convert them.
                # Eval would give "u00fc" instead of "ü" for "\"\\u00fc\"".
                s.gsub(/\\u([\da-fA-F]{4})/) { |m|
                  [$1].pack("H*").unpack("n*").pack("U*")
                }
              else
                # Don't allow arbitrary textual expressions outside of strings.
                raise if s[/\w+/] && !s[/\w+/][/^(null|undefined)$/]
                # If it's not a string then replace : and null and undefined.
                s.gsub(/:/, '=>').
                    gsub(/\bnull\b/, 'nil').
                    gsub(/\bundefined\b/, 'nil')
              end
            }.join('')
            result = eval(ruby_string)
            return result
          end


        end
      end


    end # class Bridge


  end # class Console


end # module AE
