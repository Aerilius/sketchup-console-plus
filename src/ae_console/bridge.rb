=begin
@module  Bridge
@version 3.0.0
@date    2017-08-24
@author  Andreas Eisenbarth
@license MIT License (MIT)

This Bridge provides an intuitive and asynchronous API for message passing between SketchUp's Ruby environment and dialogs.
It supports any amount of parameters of any JSON-compatible type and is uses Promises to asynchronously access return values
on success or handle failures.

It emerged from several deficiencies of SketchUp's previous callback mechanism of the class UI::WebDialog, which has been
succeeded in newer versions by UI::HtmlDialog. Thus the implementation differs between the two.
(as documented here: https://github.com/thomthom/sketchup-webdialogs-the-lost-manual).

## UI::WebDialog

Based on `execute_script` and custom protocol handler `location.href='skp:callback@parameter'`.

- Supports only one string parameter that must be escaped.
  => Add JSON support through serialization.
- Inproper Unicode support; looses properly escaped calls containing single quotes; drops repeated properly escaped backslashes.
- Maximum URL length (2083 characters) in Internet Explorer on Windows (https://support.microsoft.com/en-us/kb/208427)
  => JavaScript requestHandler writes serialized message into an input field, and the Ruby request_handler reads it out.
- Asynchronous on macOS with message loss for quick successive calls from WebDialog to SketchUp.
  => requestHandler implements a message queue and reception of a message is acknowledged fro the Ruby side.
- UI::WebDialog#execute_script adds every time a script element.
  => Clean-up script elements
- UI::WebDialog Procs are not garbage-collected, if the proc contains a reference to an object referencing the dialog they remain in memory

## UI::HtmlDialog

Based on `execute_script` and custom object `window.sketchup.callback(parameter,…)`.

- Supports JSON parameters
- Supports Unicode
- No limits on message length
- No message loss: subsequent messages don't harm/abort previous messages
  => No ack needed.
- UI::HtmlDialog#execute_script does not anymore add extra script elements (or cleans them up now).
  => No clean-up needed.
- Has a new onCompleted callback, but it does not support to return parameters
  => Keep callback mechanism.
- UI::WebDialog#get_element_value removed: No way to get data from the dialog.
  => Bridge#get makes this possible

@example Simple call
  // On the Ruby side:
  bridge.on('add_image'){ |dialog, image_path, point, width, height|
    @entities.add_image(image_path, point, width.to_l, height.to_l)
  }
  // On the JavaScript side:
  Bridge.call('add_image', 'http://www.example.com/image/9895.jpg', [10, 10, 0], '2.5m', '1.8m');

@example Log output to the Ruby Console
  Bridge.puts('Swiss "grüezi" is pronounced [ˈɡryə̯tsiː] and means "您好！" in Chinese.');

@example Log an error to the Ruby Console
  try {
    document.produceError();
  } catch (error) {
    Bridge.error(error);
  }

@example Usage with promises
  // On the Ruby side:
  bridge.on('do_calculation'){ |action_context, length, width|
    if validate(length) && validate(width)
      result = calculate(length)
      action_context.resolve(result)
    else
      action_context.reject('The input is not valid.')
    end
  }
  // On the JavaScript side:
  var promise = Bridge.get('do_calculation', length, width)
  promise.then(function (result) {
    $('#resultField').text(result);
  }, function (failureReason) {
    $('#inputField1').addClass('invalid');
    $('#inputField2').addClass('invalid');
    alert(failureReason);
  });

=end

require(File.expand_path('../promise.rb', __FILE__))
# Optionally requires 'json.rb'
# Requires modules Sketchup, UI

module AE

  module ConsolePlugin

    class Bridge

      # Add the bridge to an existing UI::WebDialog/UI::HtmlDialog.
      # This can be used for convenience and will define the bridge's methods
      # on the dialog and delegate them to the bridge.
      # @param dialog [UI::WebDialog, UI::HtmlDialog]
      # @return       [UI::WebDialog, UI::HtmlDialog] The decorated dialog
      def self.decorate(dialog)
        bridge = self.new(dialog)
        dialog.instance_variable_set(:@bridge, bridge)

        def dialog.bridge
          return @bridge
        end

        def dialog.on(name, &callback)
          @bridge.on(name, &callback)
          return self
        end

        def dialog.once(name, &callback)
          @bridge.once(name, &callback)
          return self
        end

        def dialog.off(name)
          @bridge.off(name)
          return self
        end

        def dialog.call(function, *parameters, &callback)
          @bridge.call(function, *parameters, &callback)
        end

        def dialog.get(function, *parameters)
          return @bridge.get(function, *parameters)
        end

        return dialog
      end

      # Add a callback handler. Overwrites an existing callback handler of the same name.
      # @param name            [String]             The name under which the callback can be called from the dialog.
      # @param callback        [Proc,UnboundMethod] A method or proc for the callback, if no yield block given.
      # @yield                                      A callback to be called from the dialog to execute Ruby code.
      # @yieldparam dialog     [ActionContext]      An object referencing the dialog, enhanced with methods
      #                                             {ActionContext#resolve} and {ActionContext#resolve} to return results to the dialog.
      # @yieldparam parameters [Array<Object>]      The JSON-compatible parameters passed from the dialog.
      # @return                [self]
      def on(name, &callback)
        raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
        raise(ArgumentError, "Argument `name` can not be `#{name}`.") if RESERVED_NAMES.include?(name)
        raise(ArgumentError, 'Argument `callback` must be a Proc or UnboundMethod.') unless block_given?
        @handlers[name] = callback
        return self
      end

      # Add a callback handler to be called only once. Overwrites an existing callback handler of the same name.
      # @param name            [String]             The name under which the callback can be called from the dialog.
      # @param callback        [Proc,UnboundMethod] A method or proc for the callback, if no yield block given.
      # @yield                                      A callback to be called from the dialog to execute Ruby code.
      # @yieldparam dialog     [ActionContext]      An object referencing the dialog, enhanced with methods
      #                                             {ActionContext#resolve} and {ActionContext#resolve} to return results to the dialog.
      # @yieldparam parameters [Array<Object>]      The JSON-compatible parameters passed from the dialog.
      # @return                [self]
      # TODO: Maybe allow many handlers for the same name?
      def once(name, &callback)
        raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
        raise(ArgumentError, "Argument `name` can not be `#{name}`.") if RESERVED_NAMES.include?(name)
        raise(ArgumentError, 'Argument `callback` must be a Proc or UnboundMethod.') unless block_given?
        @handlers[name] = Proc.new { |*parameters|
          @handlers.delete(name)
          callback.call(*parameters)
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

      # Call a JavaScript function with JSON parameters in the webdialog.
      # @param name        [String]        The name of a public JavaScript function
      # @param *parameters [Array<Object>] An array of JSON-compatible objects
      # TODO: Catch JavaScript errors!
      def call(name, *parameters)
        raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
        parameters_string = self.class.serialize(parameters)
        parameters_string = 'undefined' if parameters_string.nil? || parameters_string.empty?
        @dialog.execute_script("#{name}.apply(undefined, #{parameters_string})")
      end

      # Call a JavaScript function with JSON parameters in the webdialog and get the
      # return value in a promise.
      # @param  name        [String]  The name of a public JavaScript function
      # @param  *parameters [Object]  An array of JSON-compatible objects
      # @return             [Promise]
      def get(name, *parameters)
        raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
        parameter_string = self.class.serialize(parameters)
        return Promise.new { |resolve, reject|
          handler_name = create_unique_handler_name('resolve/reject')
          once(handler_name) { |action_context, success, parameters|
            if success
              resolve.call(*parameters)
            else
              reject.call(*parameters)
            end
          }
          @dialog.execute_script(
            <<-SCRIPT
            try {
                var Bridge = #{JSMODULE};
                new Bridge.Promise(function (resolve, reject) {
                    // The called function may immediately return a result or a Promise.
                    resolve(#{name}.apply(undefined, #{parameter_string}));
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

      private

      # The namespace for prefixing internal callback names to avoid clashes with code using this library.
      NAMESPACE = 'Bridge'
      # The module path of the corresponding JavaScript implementation.
      JSMODULE = 'requirejs("bridge")' # Here using requirejs, when using public javascript modules then 'Bridge'.
      # Names that are used internally and not allowed to be used as callback handler names.
      RESERVED_NAMES = []
      attr_reader :dialog

      # Create an instance of the Bridge and associate it with a dialog.
      # @param dialog [UI::HtmlDialog, UI::WebDialog]
      def initialize(dialog)
        raise(ArgumentError, 'Argument `dialog` must be a UI::HtmlDialog or UI::WebDialog.') unless defined?(UI::HtmlDialog) && dialog.is_a?(UI::HtmlDialog) || dialog.is_a?(UI::WebDialog)
        @dialog         = dialog
        @handlers       = {}

        if defined?(UI::HtmlDialog) && dialog.is_a?(UI::HtmlDialog) # SketchUp 2017+
          # Workaround issue: Failure to register new callbacks in Chromium, thus overwriting the existing, unused "LoginSuccess".
          @dialog.add_action_callback("LoginSuccess", &method(:__request_handler_htmldialog__))
        else
          @dialog.add_action_callback("#{NAMESPACE}.receive", &method(:__request_handler_webdialog__))
        end
        add_default_handlers
      end

      # Receives the raw messages from the WebDialog (Bridge.call) and calls the individual callbacks.
      # @private Not for public use.
      # @param   action_context [UI::ActionContext]
      # @param   request        [Object]
      # @private
      def __request_handler_htmldialog__(action_context, request)
        unless request.is_a?(Hash) &&
            request['id'].is_a?(Fixnum) &&
            request['name'].is_a?(String) &&
            request['parameters'].is_a?(Array)
          raise(ArgumentError, "Bridge received invalid data: \n#{value}")
        end
        id         = request['id']
        name       = request['name']
        parameters = request['parameters'] || []

        # Here we pass a wrapper around the dialog which preserves the message id to
        # identify the corresponding JavaScript callback.
        # This allows to run asynchronous code (external application etc.) and return
        # later the result to the JavaScript callback even if the dialog has continued
        # sending/receiving messages.
        if request['expectsCallback']
          response = ActionContext.new(@dialog, id)
          begin
            # Get the callback.
            unless @handlers.include?(name)
              raise(ArgumentError.new("No registered callback `#{name}` for #{@dialog} found."))
            end
            handler = @handlers[name]
            handler.call(response, *parameters)
          rescue Exception => error
            response.reject(error)
            raise(error)
          end
        else
          # Get the callback.
          unless @handlers.include?(name)
            raise(ArgumentError.new("No registered callback `#{name}` for #{@dialog} found."))
          end
          handler = @handlers[name]
          handler.call(@dialog, *parameters)
        end

      rescue Exception => error
        ConsolePlugin.error(error)
      end

      # Receives the raw messages from the WebDialog (Bridge.call) and calls the individual callbacks.
      # @param   dialog           [UI::WebDialog]
      # @param   parameter_string [String]
      def __request_handler_webdialog__(dialog, parameter_string)
        # Get message data from the hidden input element.
        value   = dialog.get_element_value("#{NAMESPACE}.requestField") # returns empty string if element not found
        request = self.class.unserialize(value)
        unless request.is_a?(Hash) &&
            request['id'].is_a?(Fixnum) &&
            request['name'].is_a?(String) &&
            request['parameters'].is_a?(Array)
          raise(ArgumentError, "Bridge received invalid data: \n#{value}")
        end
        id         = request['id']
        name       = request['name']
        parameters = request['parameters'] || []

        # Here we pass a wrapper around the dialog which preserves the message id to
        # identify the corresponding JavaScript callback.
        # This allows to run asynchronous code (external application etc.) and return
        # later the result to the JavaScript callback even if the dialog has continued
        # sending/receiving messages.
        response = (request['expectsCallback']) ? ActionContext.new(dialog, id) : dialog
        # Get the callback.
        unless @handlers.include?(name)
          error = ArgumentError.new("No registered callback `#{name}` for #{dialog} found.")
          response.reject(error)
          raise(error)
        end
        handler = @handlers[name]
        begin
          handler.call(response, *parameters)
        rescue Exception => error
          response.reject(error)
          raise(error)
        end

      rescue Exception => e
        ConsolePlugin.error(e)
      ensure
        # Acknowledge that the message has been received and enable the bridge to send
        # the next message if available.
        dialog.execute_script("#{JSMODULE}.__ack__()")
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
            parameters_string = Bridge.serialize(results)[1...-1]
            parameters_string = 'undefined' if parameters_string.nil? || parameters_string.empty?
            @dialog.execute_script("#{JSMODULE}.__resolve__(#{@id}, #{parameters_string})")
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
        def method_missing(method_name, *parameters, &block)
          return @dialog.__send__(method_name, *parameters, &block)
        end

      end # class ActionContext

      # For serializing objects, we choose JSON.
      # Objects passed between bridge instances must be of JSON-compatible types:
      #     object literal, array, string, number, boolean, null
      # If available and compatible, we prefer JSON from the standard libraries, otherwise we use a fallback JSON converter.
      if !defined?(Sketchup) || Sketchup.version.to_i >= 14
        begin
          # `Sketchup::require "json"` raises no error, but displays in the load errors popup.
          # As a workaround, we use `load`.
          load 'json.rb' unless defined?(JSON)
          # No support for option :quirks_mode ? Fallback to JSON implementation in this library.
          raise unless JSON::VERSION_MAJOR >= 1 && JSON::VERSION_MINOR >= 6

          # Serializes an object.
          # @param  object [Object]
          # @return        [String]
          # @private
          def self.serialize(object)
            # quirks_mode generates JSON from objects other than Hash and Array.
            return JSON.generate(object, {:quirks_mode => true})
          end

          # Unserializes the string representation of a serialized object.
          # @param  string [String]
          # @return        [Object]
          # @private
          def self.unserialize(string)
            return JSON.parse(string, {:quirks_mode => true})
          end

        rescue LoadError, RuntimeError # LoadError when loading 'json.rb', RuntimeError when version mismatch
          # Fallback JSON implementation.

          # @private
          def self.serialize(object)
            # Split at every even number of unescaped quotes. This gives either strings
            # or what is between strings.
            object = normalize_object(object.clone)
            json_string = object.inspect.split(/("(?:\\"|[^"])*")/).
                map { |string|
              next string if string[0..0] == '"' # is a string in quotes
              # If it's not a string then replace : and null
              string.gsub(/=>/, ':')
              .gsub(/\bnil\b/, 'null')
            }.join('')
            return json_string
          end

          # @private
          def self.unserialize(string)
            # Split at every even number of unescaped quotes. This gives either strings
            # or what is between strings.
            # ruby_string = json_string.split(/(\"(?:.*?[^\\])*?\")/).
            # The outer capturing braces () are important for that ruby keeps the separator patterns in the returned array.
            regexp_separate_strings = /("(?:\\"|[^"])*")/
            regexp_text = /[^\d\-.:{}\[\],\s]+/
            regexp_non_keyword = /^(true|false|null|undefined)$/
            ruby_string = string.split(regexp_separate_strings).
                map{ |s|
              # It is a string in quotes.
              if s[0..0] == '"'
                # Convert escaped unicode characters because eval won't convert them.
                # Eval would give "u00fc" instead of "ü" for "\"\\u00fc\"".
                s.gsub(/\\u([\da-fA-F]{4})/) { |m|
                  [$1].pack('H*').unpack('n*').pack('U*')
                }
              else
                # Don't allow arbitrary textual expressions outside of strings.
                raise(BridgeInternalError, 'JSON string contains invalid unquoted textual expression') if s[regexp_text] && !s[regexp_text][regexp_non_keyword]
                # raise if s[/(true|false|null|undefined)/] && !s[/\w+/][//] # TODO
                # If it's not a string then replace : and null and undefined.
                s.gsub(/:/, '=>').
                    gsub(/\bnull\b/, 'nil').
                    gsub(/\bundefined\b/, 'nil')
              end
            }.join('')
            result = eval(ruby_string)
            return result
          end

          private

          def normalize_object(o)
            if o.is_a?(Array)
              o.each_with_index{ |v,i|
                o[i] = (v.is_a?(Symbol)) ? v.to_s : normalize_object(v)
              }
            elsif o.is_a?(Hash)
              o.clone.each{ |k,v|
                o.delete(k)
                o[k.to_s] = (v.is_a?(Symbol)) ? v.to_s : normalize_object(v)
              }
            end
            return o
          end

        end

      end

      # An error caused by malfunctioning of this library.
      # @private
      class BridgeInternalError < StandardError
        def initialize(exception, type=exception.class.name, backtrace=(exception.respond_to?(:backtrace) ? exception.backtrace : caller))
          super(exception)
          @type = type
          set_backtrace(backtrace)
        end
        attr_reader :type
      end

      # An error caused by the remote counter-part of a bridge instance.
      # @private
      class BridgeRemoteError < StandardError
        def initialize(exception, type=exception.class.name, backtrace=(exception.respond_to?(:backtrace) ? exception.backtrace : caller))
          super(exception)
          @type = type
          set_backtrace(backtrace)
        end
        attr_reader :type
      end

      # @private
      class BridgeRemoteInternalError < BridgeRemoteError
      end

    end # class Bridge

  end

end
