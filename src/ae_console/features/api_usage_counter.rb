require 'json.rb'

module AE

  module ConsolePlugin

    # This module counts usage of API methods
    class ApiUsageCounter

      class << self
        # Find an existing and writable directory where to store user data.
        def get_data_dir
          if ENV['APPDATA']
            # Windows
            path = ENV['APPDATA']
            return path if File.exist?(path) && File.writable?(path)
          elsif ENV['HOME']
            # Free desktop standard
            path = File.join(ENV['HOME'], '.local', 'share')
            return path if File.exist?(path) && File.writable?(path)
            # OSX
            path = File.join(ENV['HOME'], 'Library', 'Application Support')
            return path if File.exist?(path) && File.writable?(path)
          end
          # Fallback 1: Plugins folder
          if File.writable?(PATH)
            path = File.join(PATH, 'data')
            return path if File.writable?(path)
          end
          # Fallback 2: user's folder.
          path = File.expand_path('~')
        end
        private :get_data_dir
      end

      DATA_DIR = File.join(get_data_dir(), 'SketchUp Ruby Console+') unless defined?(self::DATA_DIR)
      DATA_FILE = File.join(DATA_DIR, 'api_usage_statistics.json')
      DEFAULT_FILE = File.join(PATH, 'data', 'generated_api_usage_statistics.json')

      def initialize(filepath=DATA_FILE)
        @filepath = filepath
        # The data object.
        @data = Hash.new(0)
      end

      def read
        if File.exist?(@filepath)
          File.open(DEFAULT_FILE, 'r'){ |f|
            string = f.read
            @data.update(JSON.parse(string))
          }
          File.open(@filepath, 'r'){ |f|
            string = f.read
            @data.update(JSON.parse(string))
          }
          @total_count = @data.values.reduce(0, &:+)
        end
        return self
      end

      def save
        File.open(@filepath, 'w'){ |f|
          f.write(JSON.generate(@data))
        }
        return self
      end

      def used(docpath, weight=1)
        @data[docpath] += 1
      end
      
      def get_count(docpath)
        return @data[docpath]
      end

      def get_total_count
        return @total_count
      end

    end

  end

end
