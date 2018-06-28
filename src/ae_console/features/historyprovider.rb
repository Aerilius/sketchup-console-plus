module AE

  module ConsolePlugin

    class FeatureHistory

      # This class allows to register strings and later save them to a file.
      class HistoryProvider

        class << self
          # Find an existing and writable directory where to store user data.
          def get_data_dir
            if ENV["APPDATA"]
              # Windows
              path = ENV["APPDATA"]
              return path if File.exist?(path) && File.writable?(path)
            elsif ENV["HOME"]
              # Free desktop standard
              path = File.join(ENV["HOME"], ".local", "share")
              return path if File.exist?(path) && File.writable?(path)
              # OSX
              path = File.join(ENV["HOME"], "Library", "Application Support")
              return path if File.exist?(path) && File.writable?(path)
            end
            # Plugins folder
            if File.writable?(PATH)
              path = File.join(PATH, "data")
              return path if File.writable?(path)
            end
            # Fallback: user's folder.
            path = File.expand_path("~")
          end
          private :get_data_dir
        end

        @@instances = []
        DATA_DIR = File.join(get_data_dir(), "SketchUp Ruby Console+") unless defined?(self::DATA_DIR)
        MAX_LENGTH = 100 unless defined?(self::MAX_LENGTH)
        SEPARATOR_STRING = "\n###SEPARATOR###\n" unless defined?(self::SEPARATOR_STRING)
        SEPARATOR_REGEXP = /\n(?:###SEPARATOR###|SEPARATOR_TO_BE_DETERMINED)\n/ unless defined?(self::SEPARATOR_REGEXP)

        def initialize
          # Create the smallest unique id.
          @id = 0
          @id += 1 while @@instances.include?(@id)
          @@instances.push(@id)
          ObjectSpace.define_finalizer(self, Proc.new{ |id|
            @@instances.delete(@id)
          })
          # The data object.
          @data = []
          Dir.mkdir(DATA_DIR) unless File.directory?(DATA_DIR)
          # Try to load stored data.
          @path = File.join(DATA_DIR, "history#{@id}.txt")
          read()
        end

        def push(arg)
          return if arg == @data.last
          if @data.length > MAX_LENGTH
            @data.shift
          end
          @data << arg
        end
        alias_method :<<, :push

        def save
          File.open(@path, "w"){ |file|
            file.print(@data.join(SEPARATOR_STRING))
          }
        end

        def read
          if File.exist?(@path)
            string = IO.read(@path)
            @data.clear.concat(string.split(SEPARATOR_REGEXP)) if string.is_a?(String)
          end
        end
        private :read

        def close
          @@instances.delete(@id)
        end

        def to_a
          return @data.dup
        end

        def inspect
          return @data.inspect
        end
        alias_method :to_s, :inspect

      end # class HistoryProvider

    end # class FeatureHistory

  end # module ConsolePlugin

end # module AE
