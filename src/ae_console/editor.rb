module AE

  # core.rb must be loaded first.

  module ConsolePlugin

    class Editor

      def initialize(exports)
        exports.settings[:recently_opened_files] ||= []
        exports.settings[:recently_focused_lines] ||= {} # filename => line number

        exports.plugin.on(:console_added){ |console|
          dialog = console.dialog
          file_observer = FileObserver.new

          dialog.on('openpanel') { |action_context, title, directory=nil, filename=nil|
            filepath = UI.openpanel(title, directory, filename)
            if filepath.nil?
              action_context.reject('cancelled')
            else
              action_context.resolve(File.expand_path(filepath))
            end
          }

          dialog.on('readfile') { |action_context, filepath|
            filepath = File.expand_path(filepath)
            action_context.reject('File does not exist.') unless File.file?(filepath)
            File.open(filepath, 'r'){ |file|
              action_context.resolve(file.read)
              file_observer.unregister_all # Don't observe previous file anymore.
            }
          }

          dialog.on('writefile') { |action_context, filepath, content|
            File.open(filepath, 'w') { |file|
              file.puts(content)
            }
            action_context.resolve
          }

          dialog.on('observe_external_file_changes') { |action_context, filepath|
            file_observer.register(filepath, :changed) { |filepath|
              action_context.resolve(filepath)
            }
          }

          dialog.on('savepanel') { |action_context, title, directory=nil, filename=nil|
            filepath = UI.savepanel(title, directory, filename)
            if filepath.nil?
              action_context.reject('cancelled')
            else
              action_context.resolve(File.expand_path(filepath))
            end
          }

          dialog.on('search_files') { |action_context, pattern|
            # Since there can be very many files in the load path, we cache them in @files.
            # If @files has been updated within the last 30 seconds, access file paths from the cache.
            if !@files_cache || !@files_last_scan || Time.now - @files_last_scan > 30
              @files_cache = $LOAD_PATH.map{ |load_path|
                Dir.glob(load_path + '**{,/*/**}/*.{rb,js,html,htm,css}') # Recursive search
                # Dir.glob(load_path + '/*.{rb,js,html,htm,css}') # Non-recursive search
              }.flatten.uniq
              @files_last_scan = Time.now
            end
            # Search within these files.
            files = []
            if pattern.length < 5
              # For short patterns, we only want an exact match from beginning.
              regexp = Regexp.new('Plugins.' + Regexp.escape(pattern), 'i')
              files = @files_cache.select{ |file| file =~ regexp }.sort[0...20]
            else
              # For search expressions (with several word fragments), we search at any place within file paths.
              patterns = pattern.split(/\s/)
              regexp = Regexp.new( patterns.map{ |s| Regexp.escape(s) }.join('|'), 'ig' )
              amount = patterns.length
              # Filter by the amount of matches.
              files = @files_cache.select{ |file|
                matches = regexp.match(file)
                matches && matches.length == amount
              }.sort[0...20]
            end
            action_context.resolve(files)
          }

        }
      end

    end # class Editor

  end # module ConsolePlugin

end # module AE
