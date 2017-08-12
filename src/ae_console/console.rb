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

      attr_reader :dialog, :bridge

      def initialize(settings)
        @settings = settings

        # ID for every message.
        # The ids allow to track the succession of messages (which error/result was invoked by which input etc.)
        @message_id = '0'

        # Counter for evaled code (only for display in undo stack).
        @undo_counter = 0

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
      def puts(*args)
        return unless @dialog && @dialog.visible?
        args.each { |arg|
          @dialog.call('AE.Console.puts', arg.to_s, {:language => :ruby, :time => Time.now.to_f, :id => @message_id.next!})
        }
        nil
      end

      # Sends messages over the stdout/print channel to the webdialog.
      # @param args [Object] Objects that can be turned into a string.
      def print(*args)
        return unless @dialog && @dialog.visible?
        args.each { |arg|
          @dialog.call('AE.Console.print', arg.to_s, {:language => :ruby, :time => Time.now.to_f, :id => @message_id.next!})
        }
        nil
      end

      # Sends messages over the warn channel to the webdialog.
      # @param args [Object] Objects that can be turned into a string.
      def warn(*args)
        return unless @dialog && @dialog.visible?
        args.each { |arg|
          @dialog.call('AE.Console.warn', arg.to_s, {:language => :ruby, :time => Time.now.to_f, :id => @message_id.next!})
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
        @dialog.call('AE.Console.error', message, metadata)
        nil
      end

      ### Private methods

      private

      def initialize_ui
        @dialog = UI::HtmlDialog.new({
            :dialog_title    => TRANSLATE['Ruby Console+'],
            :preferences_key => "com.aerilius.console",
            :scrollable      => false,
            :resizable       => true,
            :width           => 400,
            :height          => 300,
            :left            => 200,
            :top             => 200,
            :style => UI::HtmlDialog::STYLE_DIALOG
        })
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

        @dialog.set_can_close {
          trigger(:before_close)
        }

        @dialog.set_on_closed {
          trigger(:closed)
        }
      end

      def do_eval(action_context, command, line_number=0, metadata={})
        begin
          new_metadata = {
              :language => :ruby,
              :id     => @message_id.next!,
              :source => metadata['id']
          }
          # Wrap it optionally into an operation.
          result = wrap_in_undo(@settings[:wrap_in_undo]){
            @binding.eval(command, '(eval)', line_number)
          }
          # Render the result to a string.
          unless result.is_a?(String)
            if defined?(awesome_inspect)
              result = result.awesome_inspect({:plain=>true, :index=>false})
            elsif defined?(pretty_inspect)
              result = result.pretty_inspect.chomp # Remove new line that PrettyInspect adds at the end https://www.ruby-forum.com/topic/113429
            else
              result = result.inspect
            end
          end
          # Return the result and metadata.
          new_metadata[:time] = Time.now.to_f
          action_context.resolve(result, new_metadata)
          # Maybe trigger event :eval_result here.
        rescue Exception => exception
          remove_eval_internals_from_backtrace(exception.backtrace)
          message, _metadata = get_exception_metadata(exception)
          new_metadata.merge!(_metadata)
          new_metadata[:time] = Time.now.to_f
          new_metadata[:message] = message
          action_context.reject(new_metadata)
          # Maybe trigger event :eval_error here.
        end
      end

      # Wraps a block into an operation if parameter is true.
      def wrap_in_undo(boolean, &block)
        if boolean
          @undo_counter += 1
          operation_name = TRANSLATE['Ruby Console %0 operation %1', '', @undo_counter]
          # TODO: In an MDI, this applies the operation only on the focussed model, but the ruby code could theoretically modify another model.
          Sketchup.active_model.start_operation(operation_name, true)
        end
        result = block.call
        if boolean
          Sketchup.active_model.commit_operation
        end
        return result
      rescue Exception => exception
        if boolean
          Sketchup.active_model.abort_operation
        end
        raise exception
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
        regexp = /^\(eval\)/
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
