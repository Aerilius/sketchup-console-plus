module AE

  module ConsolePlugin

    class FeatureReloadScripts

      require(File.join(PATH, 'features', 'fileobserver.rb'))

      def initialize(app)
        @app = app
        app.settings[:reload_scripts] ||= []
        @file_observer ||= FileObserver.new

        # Unregister files from settings
        app.plugin.on(:console_closed){
          if app.consoles.count == 0 # last instance closed
            @file_observer.unregister_all
          end
        }

        app.plugin.on(:console_added, &method(:initialize_console))
      end


      def initialize_console(console)
        # Register files from settings
        if @app.consoles.count == 1 # first instance opened
          @app.settings[:reload_scripts].each { |relpath|
            fullpath = relative_to_full_path(relpath)
            @file_observer.register(fullpath, :changed) { |fullpath|
              batch_reload_files([fullpath])
            }
          }
        end

        dialog = console.dialog

        dialog.on('reload') { |action_context, fullpaths|
          # Selected scripts will be reloaded.
          # Lock eventual script errors to this console so they don't appear on other consoles.
          ObjectReplacer.swap(:value, console, ConsolePlugin::PRIMARY_CONSOLE) {
            batch_reload_files(fullpaths, console)
          }
        }

        dialog.on('start_observing_file') { |action_context, relpath|
          fullpath = relative_to_full_path(relpath)
          # Load it immediately
          batch_reload_files([fullpath])
          @file_observer.register(fullpath, :changed) { |fullpath|
            batch_reload_files([fullpath])
          }
        }

        dialog.on('stop_observing_file') { |action_context, relpath|
          fullpath = relative_to_full_path(relpath)
          @file_observer.unregister(fullpath)
        }
      end

      def relative_to_full_path(relpath)
        return relpath if File.exists?(relpath)
        return $LOAD_PATH.map{ |base|
          File.join(base, relpath.to_s) if base.is_a?(String)
        }.find{ |path|
          File.exists?(path) if path.is_a?(String)
        }.to_s
      end

      def shorten_full_path(fullpath)
        return $LOAD_PATH.inject(fullpath) { |t, base_path| t.sub(base_path.chomp("/"), "…") }
      end

      def batch_reload_files(fullpaths, console=nil)
        errors = []
        fullpaths.each{ |fullpath|
          begin
            if fullpath[/\.rbe$|\.rbs$/]
              # This method may fail and return false (instead of an exception).
              # It should also handle unencrypted scripts, but it failed for me.
              unless Sketchup.load(fullpath)
                raise LoadError.new("Sketchup.load failed to load #{fullpath}")
              end
            else
              Kernel::load(fullpath)
            end
          rescue LoadError => e
            errors << e
          end
        }
        if errors.empty?
          if fullpaths.length == 1
              puts(TRANSLATE['%0 reloaded', shorten_full_path(fullpaths.first.to_s)])
          else
              puts(TRANSLATE['Scripts reloaded'])
          end
        else
          errors.each { |e|
            if console
              console.error(e)
            else
              ConsolePlugin.error(e)
            end
          }
        end
      end

      def get_javascript_path
        return 'feature_reload_scripts.js'
      end

    end # class FeatureReloadScripts

  end # module ConsolePlugin

end # module AE
