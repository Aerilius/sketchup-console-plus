module AE

  module ConsolePlugin

    # Constants
    self::PATH = File.expand_path('..', __FILE__) unless defined?(self::PATH)

    # Requirements
    %w(translate.rb
       observable.rb
       settings.rb
       object_replacer.rb
       console.rb
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
        PRIMARY_CONSOLE.value = @@consoles.first
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

    # Close all consoles.
    def self.close
      @@consoles.each{ |instance| instance.close }
      # Unregister all.
      @@consoles.clear
      # Undo setup.
      PRIMARY_CONSOLE.value = nil
      @@stdout_redirecter.disable
      @@stderr_redirecter.disable
      Kernel::untrace_var(:$!, @@script_error_catcher)
      nil
    end

    # TODO: refactor this somewhere else
    def self.error(*args)
      if PRIMARY_CONSOLE.value.nil?
        if args.first.is_a?(Exception)
          $stderr.write(args.first.message + $/)
          $stderr.write(args.first.backtrace.join($/) + $/)
        else
        puts
          $stderr.write(args.first + $/)
          if args[1].is_a?(Hash) && args[1][:backtrace]
            $stderr.write(args[1][:backtrace].join($/) + $/)
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
          :font_family    => ''
      })
      # Consoles
      @@consoles ||= []
      # Observe output of STDOUT and STDERR (#<Sketchup::Console>).
      # Therefore replace the original stdout (SKETCHUP_CONSOLE) by a modified subclass.
      @@stdout_redirecter ||= ObjectReplacer.new('$stdout', Class.new($stdout.class){
        def write(*args)
          PRIMARY_CONSOLE.value.print(*args, :backtrace => [caller.first]) unless PRIMARY_CONSOLE.value.nil?
          super
        end
      }.new)
      @@stderr_redirecter ||= ObjectReplacer.new('$stderr', Class.new($stderr.class){
        def write(*args)
          unless PRIMARY_CONSOLE.value.nil?
            if args.first && args.first[/warning/i]
              PRIMARY_CONSOLE.value.warn(*args, :backtrace => caller)
            else
              PRIMARY_CONSOLE.value.warn(*args, :backtrace => caller)
            end
          end
          super
        end
      }.new)
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
              javascript_string = nil
              if feature.respond_to?(:get_javascript_string)
                javascript_string = feature.get_javascript_string
              elsif feature.respond_to?(:get_javascript_path)
                path = File.join(PATH, 'features', feature.get_javascript_path) # relative
                path = feature.get_javascript_path unless File.exist?(path)    # absolute
                if File.exist?(path)
                  javascript_string = File.read(path)
                end
              end
              if javascript_string
                # Load into webdialog. The javascript string should use `requirejs(['app'], function(){});` to access the API.
                console.dialog.execute_script(javascript_string)
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

    ### User interface

    def self.initialize_ui
      # Command
      command = UI::Command.new(TRANSLATE['Ruby Console+']) {
        ConsolePlugin.open
      }
      if Sketchup.version.to_i >= 16
        if RUBY_PLATFORM =~ /darwin/
          command.small_icon  = command.large_icon = File.join(PATH, 'images', 'icon.pdf')
        else
          command.small_icon  = command.large_icon = File.join(PATH, 'images', 'icon.svg')
        end
      else
        command.small_icon    = File.join(PATH, 'images', 'icon_32.png')
        command.large_icon    = File.join(PATH, 'images', 'icon_48.png')
      end
      command.tooltip         = TRANSLATE['An alternative Ruby Console with many useful features.']
      command.status_bar_text = TRANSLATE['Press the enter key to evaluate the input, and use shift-enter for linebreaks.']

      # Menu
      UI.menu('Window').add_item(command)

      # Toolbar
      toolbar = UI::Toolbar.new(TRANSLATE['Ruby Console+'])
      toolbar.add_item(command)
      # Show toolbar if it was open when we shutdown.
      toolbar.restore
      # Per bug 2902434, adding a timer call to restore the toolbar. This
      # fixes a toolbar resizing regression on PC as the restore() call
      # does not seem to work as the script is first loading.
      UI.start_timer(0.1, false) {
        toolbar.restore
      }
    end
    private_class_method :initialize_ui

    ### Initialization

    unless file_loaded?(__FILE__)
      initialize_plugin
      initialize_feature_system
      initialize_ui
      file_loaded(__FILE__)
    end

  end # module ConsolePlugin

end # module AE
