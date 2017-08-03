module AE


  class Console


    self::DIR ||= File.dirname(__FILE__)
    
    # Requirements
    begin
      # Optional: AwesomePrint
      require 'ap'
    rescue LoadError
      # Optional: PrettyPrint
      begin require 'pp'; rescue LoadError; end
    end
    %w(bridge.rb
       translate.rb
       options.rb
       historyprovider.rb
       highlightentity.rb
       fileobserver.rb
       autocompleter.rb
       docprovider.rb
       docbrowser.rb
    ).each{ |file| require(File.join(DIR, file)) }


    # Constants
    unless defined?(self::CONSOLE_HTML)
      CONSOLE_HTML = File.join(DIR, 'html', 'console.html') # TODO: rename file
      DOC_DIR      = File.join(DIR, 'apis')
      SKETCHUP_DOC_URL = 'http://www.rubydoc.info/github/jimfoltz/SketchUp-Ruby-API-Doc/master/'
      OLD_STDOUT = $stdout
      OLD_STDERR = $stderr
    end


    # Load settings
    @@settings ||= Options.new(Console, {
        :verbose        => false,
        :wrap_lines     => true,
        :show_time      => false,
        :wrap_in_undo   => false,
        :verbose        => $VERBOSE,
        :language       => :ruby, # :ruby, :javascript # Not yet exposed in the UI. Important: it allows only single statements (no semicolon).
        :binding        => 'global',
        :theme          => 'ace/theme/chrome',
        :reload_scripts => {},
    })

    # Keep track of all instances.
    @@instances ||= []

    # Observe opened selected files if added to the file observer.
    # Those files can be reloaded on change.
    @@file_observer ||= FileObserver.new


    # Creates a new instance and opens a console dialog.
    # If the first instance is opened, the original Sketchup::Console is redirected
    # to this class. This method makes sure that in case of an error the original
    # Sketchup::Console is restored.
    def self.open
      replace_native_console
      DocProvider.set_directory(DOC_DIR) # TODO: create a hook/notify an observer so we can have DocProvider as plugin
      # Start the observer for script errors.
      catch_script_error if @@instances.empty?
      # Register scripts for auto-reloading
      if @@instances.empty?
        @@settings[:reload_scripts].each { |relpath, enabled|
          next unless enabled
          fullpath = $LOAD_PATH.map { |base| File.join(base, relpath.to_s) if base.is_a?(String) }.find { |path| File.exists?(path) if path.is_a?(String) }.to_s
          @@file_observer.register(fullpath, :changed) { |fullpath|
            begin
              load(fullpath)
            rescue LoadError => e
              break self.error(e)
            end
            self.puts(TRANSLATE['%0 reloaded', relpath.to_s])
          }
        }
      end
      # Create a new instance
      Console.new
    rescue Exception => e
      restore_native_console
      raise e
    end


    class << self


      # Override Sketchup::Console
      def replace_native_console
        return if $stdout.is_a?(self::StdOut) && $stderr.is_a?(self::StdErr)
        $stdout = StdOut.new
        $stderr = StdErr.new
      end
      private :replace_native_console


      # Restore Sketchup::Console
      def restore_native_console
        $stdout = OLD_STDOUT
        $stderr = OLD_STDERR
      end
      private :restore_native_console

    end


      # Closes an instance and its dialog.
    # TODO: This method makes sure that in case of an error the original Sketchup::Console
    # is restored.
    def self.close
      @@instances.each { |instance|
        instance.close()
        #self.unregister(instance)
      }
    ensure
      restore_native_console
    end


=begin
    # Unregister an instance from @@instances
    # @param [Console] instance
    # @private
    # TODO: do this in instance?
    def self.unregister(instance)
      @@instances.delete(instance)
      # Set stdout/stderr back to Sketchup::Console.
      if @@instances.empty?
        @@file_observer.unregister_all
        restore_native_console
      end
    end
=end


    # Special sub-class $stdout to delegate to our Console while preserving default behavior.
    # $stdout and $stderr are normally subclasses of IO which has more methods (<<, puts)
    # than Sketchup::Console. We keep them so minimal with only a single `write` method
    # to avoid confusion or clashes.
    class StdOut
      def write(*args)
        Console.print(*args)
        OLD_STDOUT.write(*args)
      end


      def method_missing(meth, *args)
        OLD_STDOUT.send(meth, *args)
      end
    end


    # Special sub-class $stderr to delegate to our Console while preserving default behavior.
    # $stdout and $stderr are normally subclasses of IO which has more methods (<<, puts)
    # than Sketchup::Console. We keep them so minimal with only a single `write` method
    # to avoid confusion or clashes.
    class StdErr
      def write(*args)
        Console.error(*args)
        OLD_STDERR.write(*args)
      end


      def method_missing(meth, *args)
        OLD_STDERR.send(meth, *args)
      end
    end


    ### Private class methods ###


    class << self

      # Observe script errors.
      # Since eval and $stderr (why?) don't catch script errors, we regularly look into the Ruby global $!
      @@last_error_id ||= $!.object_id


      def catch_script_error
        # Check if $! holds a new error.
        if $!.object_id != @@last_error_id
          # Output the error to the console.
          self.error($!.to_s, {:time => Time.now.to_f, :backtrace => $@})
          @@last_error_id = $!.object_id
        end
        # Call this proc again if there is still a console then.
        UI.start_timer(0.5, false) {
          catch_script_error unless @@instances.empty?
        }
      end


      private :catch_script_error

    end


    ### Send messages to consoles. ###


    # The lock variable allows messages from an instance to be directed back to the same instance.
    @@lock = nil


    def self.puts(*args)
      unless @@instances.empty?
        if @@lock
          @@lock.puts(*args)
        else
          @@instances.each { |instance|
            instance.puts(*args)
          }
        end
        return nil
      end
    end


    def self.print(*args)
      unless @@instances.empty?
        if @@lock
          @@lock.print(*args)
        else
          @@instances.each { |instance|
            instance.print(*args)
          }
        end
        return nil
      end
    end


    def self.error(*args)
      unless @@instances.empty?
        if @@lock
          @@lock.error(*args)
        else
          @@instances.each { |instance|
            instance.error(*args)
          }
        end
        return nil
      end
    end


    # Observe status of modifier keys when WebDialog has focus
    # [Hash<String,Boolean>]
    # [Boolean] 'shift' (false)
    # [Boolean] 'ctrl'  (false)
    # [Boolean] 'alt'   (false)
    @@modifier_keys = {}


    def self.shift?
      return !!@@modifier_keys[:shift] || !!@@modifier_keys["shift"]
    end


    def self.ctrl?
      return !!@@modifier_keys[:ctrl] || !!@@modifier_keys["ctrl"]
    end


    def self.alt?
      return !!@@modifier_keys[:alt] || !!@@modifier_keys["alt"]
    end


    ### Instance methods ###


    attr_reader :id


    def initialize
      # Create the smallest unique ID for this console instance.
      # This way the n-th opened console instance will have the window properties (size, position)
      # and history from the last opened n-th instance.
      @id  = 0
      @id += 1 while @@instances.find { |instance| instance.id == @id }
      @@instances[@id] = self

      # Counter for evaled code (only for display in undo stack).
      @undo_counter = 0

      # ID for every message.
      # Each sender of messages (SketchUp Ruby, each JavaScript environment) has unique message ids.
      # The ids allow to track the succession of messages (which error/result was invoked by which input etc.)
      @message_id = "ruby:#{@id}:0"

      # Create a HistoryProvider to load, record and save the history.
      @history = HistoryProvider.new

      # Set the binding in which code is evaluated
      @binding         = TOPLEVEL_BINDING
      @binding_object  = TOPLEVEL_OBJECT
      set_binding(@@settings[:binding])
      @local_variables = []

      # Create the dialog.
      @dlg = UI::WebDialog.new({
          :dialog_title    => TRANSLATE['Ruby Console+'],
          :scrollable      => false,
          :preferences_key => "AE_Console#{@id}",
          :height          => 300,
          :width           => 400,
          :left            => 200,
          :top             => 200,
          :resizable       => true
      })

      @dlg.set_file(CONSOLE_HTML)

      # Add a Bridge to handle JavaScript-Ruby communication.
      Bridge.decorate(@dlg)

      @dlg.on('translate') { |dlg|
        # Translate.
        TRANSLATE.webdialog(@dlg)
      }

      @dlg.on('get_settings') { |dlg|
        init_settings = @@settings.get_all.merge({:id => @id})
        dlg.resolve init_settings
      }

      @dlg.on('get_history') { |dlg|
        dlg.return @history.to_a
      }
=begin
      @dlg.on('eval') { |dlg, command, metadata|
        begin
          @@lock         = self
          @undo_counter += 1
          new_metadata   = {:time => Time.now.to_f, :id => @message_id.next!, :source => metadata['id']}
          # Wrap it optionally into an operation.
          # TODO: In an MDI, this works only on the focussed model, but the ruby code could theoretically modify another model.
          Sketchup.active_model.start_operation(TRANSLATE['Ruby Console %0 operation %1', @id, @undo_counter], true) if @@options[:wrap_in_undo]
          # Evaluate the code.
          # We catch errors directly inside the evaluated code so that we get correct
          # line numbers or the source of the error, otherwise we often get this file as source.
          safe_command = <<-COMMAND
            begin
              #{command}
            rescue Exception => ae_console_exception
              AE::Console.error(ae_console_exception, #{new_metadata.inspect})
              #{'Sketchup.active_model.abort_operation' if @@options[:wrap_in_undo]}
            end
          COMMAND
          begin
            # TODO: use additional parameters __FILE__, __LINE__
            result = AE::Console.unnested_eval(safe_command, @binding)
          rescue SyntaxError => e
            # This one was not caught inside the command string, because it wasn't evaluated.
            raise e
          rescue Exception
            # Already rescued and logged through evaluated command string.
          end
          Sketchup.active_model.commit_operation if @@options[:wrap_in_undo]
          unless result.is_a?(String)
            if defined?(awesome_inspect)
              result = result.awesome_inspect({:plain=>true, :index=>false})
            elsif defined?(pretty_inspect)
              result = result.pretty_inspect
            else
              result = result.inspect
            end
          end
          dlg.call("AE.Console.result", result, new_metadata)
        rescue Exception => e
          AE::Console.error(e, new_metadata)
          Sketchup.active_model.abort_operation if @@options[:wrap_in_undo]
        else
          @history << command
        ensure
          @@lock = nil
        end
      }
=end
      @dlg.on('eval') { |dlg, command, line_number=0, metadata={}|
        begin
          @@lock = self
          new_metadata = {
              :language => :ruby,
              :id     => @message_id.next!,
              :source => metadata['id']
          }
          # Wrap it optionally into an operation.
          # TODO: In an MDI, this works only on the focussed model, but the ruby code could theoretically modify another model.
          if @@settings[:wrap_in_undo]
            @undo_counter += 1
            operation_name = TRANSLATE['Ruby Console %0 operation %1', @id, @undo_counter], true
            Sketchup.active_model.start_operation(operation_name, true)
          end
          # Evaluate the code.
          result = AE::Console.unnested_eval(command, @binding, '(eval)', line_number)
          # If wrapped in an operation, commit it.
          Sketchup.active_model.commit_operation if @@settings[:wrap_in_undo]
          # Render the result to a string.
          unless result.is_a?(String)
            if defined?(awesome_inspect)
              result = result.awesome_inspect({:plain=>true, :index=>false})
            elsif defined?(pretty_inspect)
              result = result.pretty_inspect
            else
              result = result.inspect
            end
          end
          new_metadata[:time] = Time.now.to_f
          dlg.resolve(result, new_metadata)
        rescue Exception => exception
          message, _metadata = get_exception_metadata(exception)
          $stdout.write "\nAE::Console.error(#{exception.inspect}, #{_metadata})\n" # TODO: remove
          new_metadata.merge!(_metadata)
          new_metadata[:time] = Time.now.to_f
          new_metadata[:message] = message
          dlg.reject(new_metadata)
          # If wrapped in an operation, abort it.
          Sketchup.active_model.abort_operation if @@settings[:wrap_in_undo]
        else
          @history << command
        ensure
          @@lock = nil
        end
      }

      @dlg.on('reload') { |dlg, scripts|
        # Selected scripts will be reloaded.
        # Lock eventual script errors to this console so they don't appear on other consoles.
        @@lock = self
        errors = []
        scripts.each { |script|
          begin
            Sketchup.load(script)
          rescue Exception => e
            errors << e
          end
        }
        errors.each { |e| self.error(e) }
        @@lock = nil
      }

      @dlg.on('update_property') { |dlg, key, value|
        @@settings[key] = value
      }

      @dlg.on('set_binding') { |dlg, string|
        dlg.return set_binding(string)
      }

      @dlg.on('set_verbose') { |dlg, bool_or_nil|
        @@settings[:verbose] = $VERBOSE = bool_or_nil if [true, false, nil].include?(bool_or_nil)
      }

      @dlg.on('openpanel') { |dlg, title|
        filepath = UI.openpanel(title)
        if filepath.nil?
          dlg.reject
        else
          dlg.resolve(filepath)
        end
      }

      @dlg.on('readfile') { |dlg, filepath|
        dlg.reject unless File.file?(filepath)
        File.open(filepath, "rb"){ |file|
          dlg.resolve(file.read)
        }
      }

      @dlg.on('writefile') { |dlg, filepath, content|
        File.open(filepath, 'w') { |file|
          file.puts(content)
        }
      }

      @dlg.on('savepanel') { |dlg, title|
        filepath = UI.savepanel(title)
        if filepath.nil?
          dlg.reject('cancelled')
        else
          dlg.resolve(filepath)
        end
      }

      @dlg.on('search_files') { |dlg, pattern|
        # Since there can be very many files in the load path, we cache them in @files.
        # If @files has been updated within the last 30 seconds, access file paths from the cache.
        if !@files || !@files_last_scan || Time.now - @files_last_scan > 30
          @files = $LOAD_PATH.map{ |load_path|
            #Dir.glob(load_path + '**{,/*/**}/*.{rb,js,html,htm,css}')
            Dir.glob(load_path + '/*.{rb,js,html,htm,css}')
          }.flatten.uniq
          @files_last_scan = Time.now
        end
        # Search within these files.
        files = []
        if pattern.length < 5
          # For short patterns, we only want an exact match from beginning.
          regexp = Regexp.new('Plugins.' + Regexp.escape(pattern), 'i')
          files = @files.select{ |file| file =~ regexp }.sort[0...20]
        else
          # For search expressions (with several word fragments), we search at any place within file paths.
          patterns = pattern.split(/\s/)
          regexp = Regexp.new( patterns.map{ |s| Regexp.escape(s) }.join('|'), 'ig' )
          amount = patterns.length
          # Filter by the amount of matches.
          files = @files.select{ |file|
            matches = regexp.match(file)
            matches && matches.length == amount
          }.sort[0...20]
        end
        dlg.resolve(files)
      }

      @dlg.on('get_recently_edited') { |dlg|
         dlg.resolve([]) # TODO: implement this
      }

      @dlg.on('highlight_entity') { |dlg, id|
        object = ObjectSpace._id2ref(id.to_i)
        HighlightEntity.entity(object)
        # Exceptions will reject the webdialog's promise.
      }

      @dlg.on('modifier_keys') { |dlg, hash|
        @@modifier_keys.merge!(hash)
      }

      @dlg.on('highlight_point') { |dlg, point, unit|
        case unit
        when 'm' then
          point.map! { |c| c.m }
        when 'feet' then
          point.map! { |c| c.feet }
        when 'inch' then
          point.map! { |c| c.inch }
        when 'cm' then
          point.map! { |c| c.cm }
        when 'mm' then
          point.map! { |c| c.mm }
        end
        HighlightEntity.point(*point)
      }

      @dlg.on('highlight_vector') { |dlg, vector|
        HighlightEntity.vector(*vector)
      }

      @dlg.on('highlight_stop') {
        HighlightEntity.stop
      }

      @dlg.on('select_entity') { |promise, desired_name|
        SelectEntity.select_tool(desired_name, @binding) { |name|
          # Asynchronous webdialog callback.
          promise.resolve name
        }
      }

      @dlg.on('open_help') { |dlg, token_list|
        x, y, w, h, sw, sh = dlg.get_sync('AE.Window.getGeometry')
        width = [w, 500].min
        left = x + w
        left = x - w if left > sw || sw - left < x
        DocBrowser.open(left, y, width, h).lookup(token_list, @binding_object, @binding)
      }

      @dlg.on('autocomplete_token_list') { |promise, prefix, token_list|
        begin
          completions = Autocompleter.complete(prefix, token_list, @binding_object)
          completions.each{ |hash|
            hash[:meta]    = TRANSLATE[hash[:meta].to_s]
            hash[:docHTML] = DocProvider.get_documentation_html(hash[:caption])
          }
          promise.resolve completions
        rescue Autocompleter::AutocompleterException => error
          if DEBUG
            self.puts('following error is in autocomplete_token_list:')
            self.error(error)
          end
        end
      }

      @dlg.on('start_observe_file_changed') { |dlg, relpath|
        fullpath = (File.exists?(relpath)) ? relpath :
            $LOAD_PATH.map { |base| File.join(base, relpath.to_s) }.find { |path| File.exists?(path) }.to_s
        # Load it immediately
        begin
          load(fullpath)
        rescue LoadError => e
          next self.error(e)
        end
        @@file_observer.register(fullpath, :changed) { |fullpath|
          begin
            load(fullpath)
          rescue LoadError => e
            next self.error(e)
          end
          self.puts(TRANSLATE['%0 reloaded', relpath.to_s])
        }
        # Refresh reload menu list in all console instances.
        @@instances.each { |instance|
          next if instance == self
          d = instance.__send__(:instance_variable_get, :@dlg)
          next unless d && d.visible?
          d.call('AE.Console.Extensions.ReloadScripts.update', @@settings[:reload_scripts])
        }
      }

      @dlg.on('stop_observe_file_changed') { |dlg, relpath|
        fullpath = $LOAD_PATH.map { |base| File.join(base, relpath.to_s) }.find { |path| File.exists?(path) }.to_s
        @@file_observer.unregister(fullpath)
        # Refresh reload menu list in all console instances.
        @@instances.each { |instance|
          next if instance == self
          d = instance.__send__(:instance_variable_get, :@dlg)
          next unless d && d.visible?
          d.call('AE.Console.Extensions.ReloadScripts.update', @@settings[:reload_scripts])
        }
      }

      #@dlg.set_on_close {
      @dlg.set_on_closed {
        @@settings.save
        @history.save
        @history.close
        SelectEntity.deselect_tool
        #self.class.unregister(self)
        unregister(self)
      }

      @dlg.show
    end


    # Unregister an instance from @@instances
    # @param [Console] instance
    # @private
    def unregister(instance)
      @@instances.delete(instance)
      # Set stdout/stderr back to Sketchup::Console.
      if @@instances.empty?
        @@file_observer.unregister_all
        #restore_native_console # TODO: is this called on class? How to let instance call private class method?
      end
    end
    private :unregister


    # Shows the console instance's dialog.
    def show
      if @dlg.visible?
        @dlg.bring_to_front
      else
        @dlg.show
      end
    end


    # Closes the console instance.
    def close
      @dlg.close
      self.class.unregister(self)
    end


    # Redefine the inspect method to give shorter output.
    # @override
    # @return [String]
    def inspect
      return "#<#{self.class}:0x#{(self.object_id << 1).to_s(16)}>"
    end


    # This method sends messages over the stdout/puts channel to the webdialog.
    # @param [Object] args Objects that can be turned into a string.
    def puts(*args)
      return unless @dlg && @dlg.visible?
      args.each { |arg|
        @dlg.call('AE.Console.puts', arg.to_s, {:language => :ruby, :time => Time.now.to_f, :id => @message_id.next!})
      }
      return nil
    end


    # This method sends messages over the stdout/print channel to the webdialog.
    # @param [Object] args Objects that can be turned into a string.
    def print(*args)
      return unless @dlg && @dlg.visible?
      args.each { |arg|
        @dlg.call('AE.Console.print', arg.to_s, {:language => :ruby, :time => Time.now.to_f, :id => @message_id.next!})
      }
      return nil
    end


    # This method sends messages over the stdout/puts channel to the webdialog.
    # @param [Exception,String] exception an exception object or a string of an error message
    # @param [Hash] _metadata if the first argument is a string
    # TODO: Maybe use Exception#set_backtrace ?
    def error(exception, _metadata=nil)
      return unless @dlg && @dlg.visible?
      metadata = {:language => :ruby, :time => Time.now.to_f}
      metadata.merge!(_metadata) if _metadata.is_a?(Hash)
      metadata[:id] = @message_id.next! unless metadata.include?(:id)
      if exception.is_a?(Exception)
        # Errors of console input would somewhen be traced to this file,
        # so we filter out this file, and break the backtrace.
        message                    = exception.message.gsub(/#{__FILE__}(?:\:\d+)\:/, "")
        this_file                  = Regexp.new(__FILE__)
        backtrace                  = (exception.backtrace || []).inject([]) { |selected, trace|
          break selected << '(eval)' if trace[this_file]
          selected << trace
        }
        metadata[:backtrace]       = backtrace
        # The backtrace contains often long file paths. Here we give shorter paths:
        metadata[:backtrace_short] = backtrace.map { |trace|
          $LOAD_PATH.inject(trace) { |t, base_path| t.sub(base_path.chomp("/"), "…/") }
        }
        @dlg.call('AE.Console.error', "#{exception.class.name}: #{message}", metadata)
      else # String
        message = exception.to_s
        if metadata[:backtrace]
          metadata[:backtrace_short] = metadata[:backtrace].compact.map { |trace|
            $LOAD_PATH.inject(trace) { |t, base_path| t.sub(base_path.chomp("/"), "…/") }
          }
        end
        if message[/warning/i]
          @dlg.call('AE.Console.warn', message, metadata)
        else
          @dlg.call('AE.Console.error', message, metadata)
        end
      end
      nil
    end


    # This method sends messages over the stdout/puts channel to the webdialog.
    # @param [Exception,String] exception an exception object or a string of an error message
    # @param [Hash] _metadata if the first argument is a string
    # TODO: Maybe use Exception#set_backtrace ?
    def error(exception, metadata={})
      $stdout.write "\nAE::Console.error(#{exception.inspect}, #{metadata})\n" # TODO: remove
      return unless @dlg && @dlg.visible?
      if exception.is_a?(Exception)
        message, _metadata = get_exception_metadata(exception)
        metadata.merge!(_metadata)
      else # String
        metadata[:backtrace_short] = shorten_backtrace(metadata[:backtrace]) if metadata.include?(:backtrace)
        message = exception.to_s
      end
      metadata = {
          :language => :ruby,
          :time     => Time.now.to_f
      }.merge(metadata).merge({
          :id => @message_id.next!
      })
      if message[/warning/i]
        @dlg.call('AE.Console.warn', message, metadata)
      else
        @dlg.call('AE.Console.error', message, metadata)
      end
      nil
    end


    def get_exception_metadata(exception)
      metadata = {
          :backtrace       => exception.backtrace,
          :backtrace_short => shorten_backtrace(exception.backtrace)
      }
      message = "#{exception.class.name}: #{exception.message}"
      return message, metadata
    end
    private :get_exception_metadata


    # The backtrace contains often long file paths. Here we give shorter paths:
    def shorten_backtrace(backtrace)
      return nil unless backtrace.is_a?(Array)
      return backtrace.compact.map { |trace|
        $LOAD_PATH.inject(trace) { |t, base_path| t.sub(base_path.chomp("/"), "…") }
      }
    end
    private :shorten_backtrace


    # This methods sets @binding of the object that is referenced by the given string.
    # @param [String] string of a reference name
    # @return [String] string of the reference to which the binding was actually set (the same on success, different on failure).
    def set_binding(string)
      # Shortcuts
      if string.is_a?(Binding)
        @binding = string
        @binding_object = eval('self', @binding)
        return string # TODO: Here the return value is not optimal, it should be a string of the reference name.
      elsif string.is_a?(String) && string == 'global'
        @binding            = TOPLEVEL_BINDING
        @binding_object     = TOPLEVEL_OBJECT
        @@settings[:binding] = string
        return string
      end
      begin
        # Validation:
        # Allow global, class and instance variables, also nested modules or classes ($, @@, @, ::).
        # Do not allow any syntactic characters like braces or operators etc.
        #string = string[/(\$|@@?)?[^\!\"\'\`\@\$\%\|\&\/\(\)\[\]\{\}\,\;\?\<\>\=\+\-\*\/\#\~\\]+/] #"
        token_list = string.split(/\b/)
        # Get the object.
        object = AE::Console::Autocompleter.resolve_object(token_list, @binding_object)
        raise StandardError if object.nil?
        # Get the binding of the object.
        @binding        = object.instance_eval { binding }
        @binding_object = object
      rescue
        @binding        = TOPLEVEL_BINDING
        @binding_object = TOPLEVEL_OBJECT
        return @@settings[:binding] = 'global'
      else
        # If successfull, remember current binding in options.
        @@settings[:binding] = string
        return string
      end
    end


  end # class Console


end # module AE


# Eval outside of any module nesting
def (AE::Console).unnested_eval(*args)
  return eval(*args)
end


AE::Console::TOPLEVEL_OBJECT = eval('self') unless defined?(AE::Console::TOPLEVEL_OBJECT )
