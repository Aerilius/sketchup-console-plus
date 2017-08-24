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
  @bridge.on("do_calculation") { |action_context, length, width|
    if validate(length) && validate(width)
      result = calculate(length)
      action_context.resolve(result)
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

  module ConsolePlugin

    class Bridge

      # Add the bridge to an existing UI::WebDialog/UI::HtmlDialog.
      # This can be used for convenience and will define the bridge's methods
      # on the dialog and delegate them to the bridge.
      # @param dialog [UI::WebDialog, UI::HtmlDialog]
      # @return [UI::WebDialog, UI::HtmlDialog] The decorated dialog
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

      # The namespace for prefixing internal callback names to avoid clashes with code using this library.
      NAMESPACE = 'Bridge'
      # The module path of the corresponding JavaScript implementation.
      JSMODULE = 'requirejs("bridge")' # Here using requirejs, when using public modules then 'Bridge'.

      # The url which responds to requests.
      URL_RECEIVE = "LoginSuccess" # Workaround issue: Failure to register new callbacks in Chromium, thus overwriting existing ones.

      # Names that are used internally and not allowed to be used as callback handler names.
      RESERVED_NAMES = []

      attr_reader :dialog

      # Add a callback handler. Overwrites an existing callback handler of the same name.
      # @param name           [String]             The name under which the callback can be called from the dialog.
      # @param callback       [Proc,UnboundMethod] A method or proc for the callback, if no yield block given.
      # @yield  A callback to be called from the dialog to execute Ruby code.
      # @yieldparam dialog    [ActionContext]      An object referencing the dialog, enhanced with methods
      #                                            {ActionContext#resolve} and {ActionContext#resolve} to return results to the dialog.
      # @yieldparam arguments [Array<Object>]      The JSON-compatible arguments passed from the dialog.
      # @return               [self]
      def on(name, callback=nil, &callback_)
        raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
        raise(ArgumentError, "Argument `name` can not be `#{name}`.") if RESERVED_NAMES.include?(name)
        raise(ArgumentError, 'Argument `callback` must be a Proc or UnboundMethod.') unless block_given? || callback.respond_to?(:call)
        callback      ||= callback_
        @handlers[name] = callback
        return self
      end

      # Add a callback handler to be called only once. Overwrites an existing callback handler of the same name.
      # @param name           [String]             The name under which the callback can be called from the dialog.
      # @param callback       [Proc,UnboundMethod] A method or proc for the callback, if no yield block given.
      # @yield  A callback to be called from the dialog to execute Ruby code.
      # @yieldparam dialog    [ActionContext]      An object referencing the dialog, enhanced with methods
      #                                            {ActionContext#resolve} and {ActionContext#resolve} to return results to the dialog.
      # @yieldparam arguments [Array<Object>]      The JSON-compatible arguments passed from the dialog.
      # @return               [self]
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
      # @param  name [String]
      # @return      [self]
      def off(name)
        raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
        @handlers.delete(name)
        return self
      end

      # Call a JavaScript function with JSON arguments in the webdialog.
      # @param name      [String]        The name of a public JavaScript function
      # @param arguments [Array<Object>] An array of JSON-compatible objects or Callables (Proc, UnboundMethod)
      # TODO: Catch JavaScript errors!
      def call(name, *arguments)
        raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
        arguments = self.class.serialize(arguments)
        arguments = 'undefined' if arguments.nil? || arguments.empty?
        @dialog.execute_script("#{name}.apply(undefined, #{arguments})")
      end

      # Call a JavaScript function with JSON arguments in the webdialog and get the
      # return value in a promise.
      # @param  name      [String]  The name of a public JavaScript function
      # @param  arguments [Object]  An array of JSON-compatible objects
      # @return           [Promise]
      # This does the same as writing the function's return value to an input field
      # and reading the value (using the old UI::WebDialog).
      def get(name, *arguments)
        raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
        arguments = self.class.serialize(arguments)
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
            try {
                var Bridge = #{JSMODULE};
                new Bridge.Promise(function (resolve, reject) {
                    // The called function may immediately return a result or a Promise.
                    resolve(#{name}.apply(undefined, #{arguments}));
                }).then(function (result) {
                    Bridge.call('#{handler_name}', true, result);
                }, function (error) {
                    Bridge.call('#{handler_name}', false, error.name + ': ' + error.message);
                });
            } catch (error) {
                Bridge.call('#{handler_name}', false, error.name + ': ' + error.message);
                Bridge.error(error);
            }
            SCRIPT
          )
        }
      end

      def get_sync(name, *arguments)
        raise(ArgumentError, 'Bridge#get_sync is not supported for UI::HtmlDialog because of missing get_element_value')
        raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
        arguments = self.class.serialize(arguments)[1...-1]
        arguments = 'undefined' if arguments.nil? || arguments.empty?
        success = @dialog.execute_script("#{JSMODULE}.responseHandler( #{name}(#{arguments}) )");
        result = @dialog.get_element_value("#{JSMODULE}.responseField")
        result = self.class.unserialize(result)
        return result
      end

      private

      # Create an instance of the Bridge and associate it with a dialog.
      # @param dialog [UI::WebDialog, UI::HtmlDialog]
      def initialize(dialog)
        raise(ArgumentError, 'Argument `dialog` must be a UI::WebDialog.') unless dialog.is_a?(UI::WebDialog) || defined?(UI::HtmlDialog) && dialog.is_a?(UI::HtmlDialog)
        @dialog         = dialog
        @handlers       = {}
        @handlers_show  = []
        @handlers_close = []

        # SketchUp does not release procs of WebDialogs. Because of that, we need to
        # make sure that the proc contains no reference to this instance. The proc
        # receives a reference to this dialog, so it can call the follow-up method #action_callback.
        @dialog.add_action_callback(URL_RECEIVE) { |action_context, request|
          begin
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
            response = ActionContext.new(@dialog, id)
            # Get the callback.
            unless @handlers.include?(name)
              error = ArgumentError.new("No registered callback `#{name}` for #{@dialog} found.")
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
            ConsolePlugin.error(e)
          end
        }

        add_default_handlers
      end

      # Add additional optional handlers for calls from JavaScript to Ruby.
      def add_default_handlers
        # Puts (for debugging)
        @handlers["#{NAMESPACE}.puts"] = Proc.new { |dialog, *arguments|
          puts(*arguments.map { |argument| argument.inspect })
        }
        RESERVED_NAMES << "#{NAMESPACE}.puts"

        # Error channel (for debugging)
        @handlers["#{NAMESPACE}.error"] = Proc.new { |dialog, type, message, backtrace|
          ConsolePlugin.error(type + ': ' + message, {:language => 'javascript', :backtrace => backtrace})
        }
        RESERVED_NAMES << "#{NAMESPACE}.error"
      end

      # Create a string which has not yet been registered as callback handler, to avoid collisions.
      # @param  string [String]
      # @return        [String]
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
      class ActionContext < Promise::Deferred

        # @param dialog [UI::WebDialog, UI::HtmlDialog]
        # @param id     [Fixnum]
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
              @dialog.execute_script("#{JSMODULE}.__resolve__(#{@id}, #{arguments})")
            end
            nil
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
            @dialog.execute_script("#{JSMODULE}.__reject__(#{@id}, #{reason})")
            nil
          }
          # Register these two handlers.
          self.promise.then(on_resolve, on_reject)
          @dialog = dialog
          @id     = id
        end

        alias_method :return, :resolve

        # Delegate other method calls to the dialog.
        # @see UI::WebDialog
        def method_missing(method_name, *arguments, &block)
          return @dialog.__send__(method_name, *arguments, &block)
        end

      end # class ActionContext

      # For serializing objects, we choose JSON.
      # If available and compatible, we prefer JSON from the standard libraries.
      if Sketchup.version.to_i >= 14
        begin
          # `Sketchup::require "json"` raises no error, but displays in the load errors popup.
          load 'json.rb' unless defined?(JSON)
          raise unless JSON::VERSION_MAJOR >= 1 && JSON::VERSION_MINOR >= 6 # support of option :quirks_mode

          # Serializes an object.
          # @param  object [Object]
          # @return        [String]
          # @private
          def self.serialize(object)
            # quirk_mode generates JSON from objects other than Hash and Array.
            # Attention! JSON in SketchUp's Ruby 2.0 standard lib does not fully implement quirk_mode.
            # return JSON.generate(object, {:quirk_mode => true})
            return JSON.generate([object])[1...-1]
          end

          # Unserializes the string representation of a serilized object.
          # @param  string [String]
          # @return        [Object]
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

  end # module ConsolePlugin

end # module AE
