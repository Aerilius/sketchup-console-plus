module AE

  module ConsolePlugin

    # Requirements
    %w(observable.rb
       bridge.rb
       object_replacer.rb
    ).each{ |file| require(File.join(PATH, file)) }
    begin
      # Optional: AwesomePrint
      require 'ap'
    rescue LoadError
      # Optional: PrettyPrint
      begin require 'pp'; rescue LoadError; end
    end

    class Console

      include Observable

      CONSOLE_HTML = File.join(PATH, 'html', 'console.html') unless defined?(self::CONSOLE_HTML)

      attr_reader :dialog, :bridge, :settings

      def initialize(settings)
        @settings = settings

        # ID for every message.
        # The ids allow to track the succession of messages (which error/result was invoked by which input etc.)
        @message_id = '0'

        @binding = ::TOPLEVEL_BINDING

        initialize_ui
      end

      ### Console instance methods

      def show
        @dialog.show
        nil
      end

      def close
        @dialog.close
        nil
      end

      ### Console API methods

      # Sends messages over the stdout/puts channel to the webdialog.
      # @param args [Object] Objects that can be turned into a string.
      def puts(*args, backtrace: nil)
        return unless @dialog && @dialog.visible?
        args.each { |arg|
          message = ensure_valid_encoding(arg.to_s)
          metadata = {
            :language => :ruby,
            :time => Time.now.to_f,
            :id => @message_id.next!,
            :backtrace => backtrace
          }
          trigger(:puts, message, metadata)
          @dialog.call('Console.puts', message, metadata)
        }
        nil
      end

      # Sends messages over the stdout/print channel to the webdialog.
      # @param args [Object] Objects that can be turned into a string.
      def print(*args, backtrace: nil)
        return unless @dialog && @dialog.visible?
        args.each { |arg|
          message = ensure_valid_encoding(arg.to_s)
          metadata = {
            :language => :ruby,
            :time => Time.now.to_f,
            :id => @message_id.next!,
            :backtrace => backtrace
          }
          trigger(:print, message, metadata)
          @dialog.call('Console.print', message, metadata)
        }
        nil
      end

      # Sends messages over the warn channel to the webdialog.
      # @param args [Object] Objects that can be turned into a string.
      def warn(*args, backtrace: nil)
        return unless @dialog && @dialog.visible?
        args.each { |arg|
          message = arg.to_s
          metadata = {
            :language => :ruby,
            :time => Time.now.to_f,
            :id => @message_id.next!,
            :backtrace => backtrace,
            :backtrace_short => shorten_paths_in_backtrace(backtrace)
          }
          trigger(:warn, message, metadata)
          @dialog.call('Console.warn', message, metadata)
        }
        nil
      end

      # Sends messages over the stderr/error channel to the webdialog.
      # @param exception [Exception,String] an exception object or a string of an error message
      # @param _metadata [Hash] if the first argument is a string
      def error(exception, metadata={})
        return unless @dialog && @dialog.visible?
        if exception.is_a?(Exception)
          message, _metadata = get_exception_metadata(exception)
          metadata.merge!(_metadata)
        else # String
          if metadata.include?(:backtrace)
            metadata[:backtrace_short] = shorten_paths_in_backtrace(metadata[:backtrace])
          end
          message = exception.to_s
        end
        metadata[:language] ||= :ruby
        metadata[:time] ||= Time.now.to_f # seconds
        metadata[:id] = @message_id.next!
        trigger(:error, exception, {:message => message}.update(metadata))
        @dialog.call('Console.error', message, metadata)
        nil
      end

      ### Private methods

      private

      def initialize_ui
        properties = {
            :dialog_title    => TRANSLATE['Ruby Console+'],
            :preferences_key => 'com.aerilius.console',
            :scrollable      => false,
            :resizable       => true,
            :width           => 400,
            :height          => 300,
            :left            => 200,
            :top             => 200,
        }
        if defined?(UI::HtmlDialog)
          properties[:style] = UI::HtmlDialog::STYLE_DIALOG
          [:width, :height, :left, :top].each{ |property| properties[property] * UI.scale_factor }
          @dialog = UI::HtmlDialog.new(properties)
        else
          @dialog = UI::WebDialog.new(properties)
        end
        @dialog.set_file(CONSOLE_HTML)

        # Add a Bridge to handle JavaScript-Ruby communication.
        @bridge = Bridge.decorate(@dialog)

        @dialog.on('loaded') { |action_context|
          trigger(:shown)
        }

        @dialog.on('translate') { |action_context|
          # Translate.
          TRANSLATE.webdialog(@dialog)
        }

        @dialog.on('get_settings') { |action_context| 
          action_context.resolve @settings.to_hash
        }

        @dialog.on('update_property') { |action_context, key, value|
          @settings[key] = value
        }

        @dialog.on('eval') { |action_context, command, line_number=0, metadata={}|
          ObjectReplacer.swap(:value, self, PRIMARY_CONSOLE) {
            do_eval(action_context, command, line_number, metadata)
          }
        }

        if @dialog.respond_to?(:set_can_close) # UI::HtmlDialog
          @dialog.set_can_close {
            trigger(:before_close)
          }
        end

        if @dialog.respond_to?(:set_on_closed) # UI::HtmlDialog
          @dialog.set_on_closed {
            trigger(:closed)
          }
        elsif @dialog.respond_to?(:set_on_close) # UI::WebDialog
          @dialog.set_on_close {
            trigger(:closed)
          }
        end
      end

      def do_eval(action_context, command, line_number=0, metadata={})
        begin
          new_metadata = {
              :language => :ruby,
              :id     => @message_id.next!,
              :source => metadata['id']
          }
          trigger(:eval, command, metadata)
          # Evaluate the command.
          result = @binding.eval(command, '(eval)', line_number)
          # Render the result to a string.
          result_string = ensure_valid_encoding(result_to_string(result))
          # Return the result and metadata.
          new_metadata[:time] = Time.now.to_f
          trigger(:result, result, {:result_string => result_string}.update(new_metadata))
          action_context.resolve({:result => result_string, :metadata => new_metadata})
          # Take care that no code after resolving the promise resolve it again 
          # or raises an exception and tries to rejects the resolved promise!
        rescue Exception => exception
          remove_eval_internals_from_backtrace(exception.backtrace)
          message, _metadata = get_exception_metadata(exception)
          new_metadata.merge!(_metadata)
          new_metadata[:time] = Time.now.to_f
          new_metadata[:message] = message
          trigger(:error, exception, {:message => message}.update(new_metadata))
          action_context.reject(new_metadata)
        end
      end

      # Render the result object to a string.
      def result_to_string(object)
        if object.is_a?(String) then
          return object
        else
          if defined?(awesome_inspect)
            return object.awesome_inspect({:plain=>true, :index=>false})
          elsif defined?(pretty_inspect)
            return object.pretty_inspect.chomp # Remove new line that PrettyInspect adds at the end https://www.ruby-forum.com/topic/113429
          else
            return object.inspect
          end
        end
      end

      # Replace invalid bytes in a string (for display only!) so it can be included in UTF-8 JSON.
      def ensure_valid_encoding(string)
        if string.is_a?(String) && 
           (!string.valid_encoding? ||
            string.encoding == Encoding::BINARY && (string.unicode_normalize rescue true))
          return string.encode(Encoding::UTF_8, {:invalid => :replace, :undef => :replace})
        else
          return string
        end
      end

      # Create a hash from an exception object.
      def get_exception_metadata(exception)
        metadata = {
          :backtrace       => exception.backtrace,
          :backtrace_short => shorten_paths_in_backtrace(exception.backtrace)
        }
        message = "#{exception.class.name}: #{exception.message}"
        return message, metadata
      end

      # Shortens file paths in the backtrace relative to a load path as root.
      def shorten_paths_in_backtrace(backtrace)
        return backtrace unless backtrace.is_a?(Array)
        return backtrace.compact.map { |trace|
          shorten_paths(trace)
        }
      end

      # Shorten a file path relative to a load path as root.
      def shorten_paths(string_with_paths)
        $LOAD_PATH.inject(string_with_paths) { |string, base_path| string.gsub(base_path.chomp('/'), '…') }
      end

      # Removes traces below the first trace referring to eval.
      # This is useful to hide internals and for exceptions that do not originate in this file.
      def remove_eval_internals_from_backtrace(backtrace)
        regexp = /^\(eval\)|^<main>/ # SketchUp 2017 | SketchUp 2014+
        line_number = backtrace.length
        until regexp =~ backtrace[line_number-1] || line_number == 0
          line_number -= 1
        end
        backtrace.slice!(line_number..-1)
      end

      # Removes traces from the first trace referring to this file and downwards.
      # This is useful to hide internals and for exceptions that do not originate in this file.
      def remove_this_file_from_backtrace(backtrace)
        regexp = %r"#{Regexp.quote(__FILE__)}"o
        line_number = 0
        until regexp =~ backtrace[line_number] || line_number == 0
          line_number += 1
        end
        backtrace.slice!(line_number..-1)
      end

    end # class Console

  end # module ConsolePlugin

end # module AE
