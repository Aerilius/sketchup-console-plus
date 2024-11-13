module AE

  module ConsolePlugin

    # Constants
    self::PATH = File.expand_path('..', __FILE__) unless defined?(self::PATH)

    # Requirements
    %w(
       console.rb
       object_replacer.rb
       observable.rb
       settings.rb
       translate.rb
       ui.rb
       version.rb
    ).each{ |file| require(File.join(PATH, file)) }

    # Constants
    self::TRANSLATE = Translate.new('console.strings') unless defined?(self::TRANSLATE)

    extend Observable

    ### Console instances

    # Creates and opens a new console instance.
    # @return [Console]
    def self.open
      # Open a console.
      console = Console.new(@@settings)
      # Register it.
      @@consoles << console
      console.show
      # When this console will be closed, unregister it properly.
      console.on(:closed){
        @@consoles.delete(console)
        PRIMARY_CONSOLE.value = @@consoles.first # or nil
        if @@consoles.empty?
          # Undo setup.
          @@stdout_redirecter.disable
          @@stderr_redirecter.disable
          Kernel::untrace_var(:$!, @@script_error_catcher)
        end
        trigger(:console_closed, console)
      }
      # Initial setup when opening consoles.
      if @@consoles.length == 1
        PRIMARY_CONSOLE.value = @@consoles.first
        # Trick: When debugging Console with `puts`, disable this.
        @@stdout_redirecter.enable
        @@stderr_redirecter.enable
        Kernel::trace_var(:$!, @@script_error_catcher)
      end
      trigger(:console_added, console)
      return console
    end

    public_class_method :open # Change to public

    # Close all consoles.
    def self.close
      @@consoles.each{ |instance| instance.close }
      # Unregister all.
      @@consoles.clear
      nil
    end

    # TODO: refactor this somewhere else
    def self.error(*args)
      if PRIMARY_CONSOLE.value.nil?
        if args.first.is_a?(Exception)
          $stderr.write(args.first.message + $/)
          $stderr.write(args.first.backtrace.join($/) + $/)
        else
          $stderr.write(args.first + $/)
          if args[1].is_a?(Hash) && args[1][:backtrace]
            $stderr.write(args[1][:backtrace].join($/))
          end
        end
      else
        PRIMARY_CONSOLE.value.error(*args)
      end
    end

    ### Plugin

    # Constant pointer that points to a console instance or nil.
    #
    # This technique is used to let an anonymous class access a reference with 
    # mutable value outside of it (it cannot see class or instance variables outside).
    #
    # We use this one as a lock variable. Must be accessible by ConsolePlugin::Console instances.
    self::PRIMARY_CONSOLE = Struct.new(:value).new(nil) unless defined?(self::PRIMARY_CONSOLE)

    # When the Ruby console is subclassed, the caller of the 'write' method contains all nested calls of the subclassed methods.
    # In order to get the original caller, we need to detect which calls come from subclasses.
    self::IGNORED_CONSOLE_SUBCLASSERS = [/testup[\/\\]console\.rb/] unless defined?(self::IGNORED_CONSOLE_SUBCLASSERS)

    class StdoutRedirecter
      def initialize(original_stdout)
        @original_stdout = original_stdout
      end

      def write(*args)
        _caller = [caller.find{ |s| ConsolePlugin::IGNORED_CONSOLE_SUBCLASSERS.none?{ |r| s[r] } }]
        ConsolePlugin::PRIMARY_CONSOLE.value.print(*args, :backtrace => _caller) unless ConsolePlugin::PRIMARY_CONSOLE.value.nil?
        args.each{ |arg| @original_stdout.write(arg) }
      end

      def flush
        @original_stdout.flush
      end
    end

    class StderrRedirecter
      def initialize(original_stderr)
        @original_stderr = original_stderr
      end

      def write(*args)
        unless PRIMARY_CONSOLE.value.nil?
          if args.first && args.first[/warning/i]
            PRIMARY_CONSOLE.value.warn(*args, :backtrace => caller)
          else
            PRIMARY_CONSOLE.value.warn(*args, :backtrace => caller)
          end
        end
        args.each{ |arg| @original_stderr.write(arg) }
      end

      def flush
        @original_stderr.flush
      end
    end

    def self.initialize_plugin
      # Load settings
      @@settings ||= Settings.new('AE/Console').load({
          :console_active => true,
          :fontSize       => 12,
          :useWrapMode    => true,
          :tabSize        => 2,
          :useSoftTabs    => true,
          :binding        => 'global',
          :theme          => 'ace/theme/chrome',
          :font_family    => '',
          :evaluationKeyBinding => 'enter', # or 'ctrl-enter' or 'shift-enter'
      })
      # Consoles
      @@consoles ||= []
      
      # Use the predefined classes
      @@stdout_redirecter ||= ObjectReplacer.new('$stdout', StdoutRedirecter.new($stdout))
      @@stderr_redirecter ||= ObjectReplacer.new('$stderr', StderrRedirecter.new($stderr))
      
      # Eval and $stderr do not catch script errors (why?), but global variable `$!` does.
      @@script_error_catcher ||= Proc.new{
        unless PRIMARY_CONSOLE.value.nil?
           PRIMARY_CONSOLE.value.error($!.to_s, {:time => Time.now.to_f, :backtrace => $@})
        end
      }
    end
    private_class_method :initialize_plugin

    ### Features

    # Registers manually a feature. 
    # @param feature_class [Class] A subclass of Feature (not an instance). 
    #                              On instantiation it will be given an object 
    #                              to access and hook into the console(s).
    def self.register_feature(feature_class)
      raise ArgumentError unless feature_class.is_a?(Class)
      return if @@registered_features.find{ |feature| feature.is_a?(feature_class) }
      @@registered_features << feature_class.new(@@feature_access)
      nil
    end

    def self.initialize_feature_system
      # Extensions
      @@registered_features ||= []
      unless defined?(@@feature_access) # only once
        # Shared object
        @@feature_access ||= Struct.new(:consoles, :settings, :plugin).new(@@consoles, @@settings, self)
        # Load JavaScript into UI when UI is shown.
        self.on(:console_added){ |console|
          console.on(:shown){ |dialog|
            @@registered_features.each{ |feature|
              # Load into webdialog. The javascript should use `requirejs(['app'], function(){});` to access the API.
              if feature.respond_to?(:get_javascript_string)
                javascript_string = feature.get_javascript_string
                console.dialog.execute_script(
                  "var element = document.createElement('script');
                  element.innerHTML = #{javascript_string.inspect};
                  document.head.appendChild(element);")
              elsif feature.respond_to?(:get_javascript_path)
                path = File.join(PATH, 'features', feature.get_javascript_path) # relative
                path = feature.get_javascript_path unless File.exist?(path)     # absolute
                console.dialog.execute_script(
                  "var element = document.createElement('script'); 
                  element.src = #{path.inspect}; 
                  document.head.appendChild(element);")
              end
            }
          }
        }
      end

      # Load the editor.
      load(File.join(PATH, 'editor.rb'))
      register_feature(Editor)

      # Find and load feature files.
      Dir.glob(File.join(PATH, 'features', 'feature_*.rb')).each{ |path|
        load(path)
      }
      # Register features.
      constants.select{ |c| c[/^Feature/] }
      .map{ |c| const_get(c) }
      .grep(Class)
      .each{ |featureClass|
        register_feature(featureClass)
      }
    end
    private_class_method :initialize_feature_system

    ### Initialization

    unless file_loaded?(__FILE__)
      initialize_plugin
      initialize_feature_system
      initialize_ui
      file_loaded(__FILE__)
    end

  end # module ConsolePlugin

end # module AE
