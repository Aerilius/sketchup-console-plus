module AE

  module ConsolePlugin

    class FileObserver

      # Create a new file observer.
      # @param  [Numeric] interval  The interval in seconds to check all observed file paths.
      def initialize(interval=2)
        @supported_events = [:created, :changed, :deleted]
        @observers        = {}
        @timer            = nil
        @interval         = (interval.is_a?(Numeric) && interval > 0) ? interval : 2 # in seconds
      end

      # Register a handler to do something on an event on a specific file.
      # @param  [String] path      The path of a file.
      # @param  [Symbol] event     The event to listen for, one of [:created, :changed, :deleted]
      # @yield                     The action to do when the event occurs.
      # @yieldparam [String] path  The file path
      def register(path, event, &callback)
        raise ArgumentError unless path.is_a?(String) && @supported_events.include?(event) && block_given?
        # If this is the first registered event, we need to start the timer.
        if @observers.empty?
          @timer = UI.start_timer(@interval, true) { check_files }
          check_files
        end
        # Register the event
        @observers[path]        ||= {}
        @observers[path][event]   = callback
        exists                    = File.exist?(path)
        @observers[path][:exists] = exists
        if exists
          @observers[path][:mtime] = File.stat(path).mtime.to_i
        end
      end

      # Unregister a handler.
      # @param  [String] path   The path of the file which should not be observed anymore.
      # @param  [Symbol] event  The event to unregister. If not given, all events for that file are unregistered.
      def unregister(path, event=nil)
        if event
          @observers[path].delete(event)
        else # all events for that path
          @observers.delete(path)
        end
        # If no events are left, we don't need to check them.
        if @timer && @observers.empty?
          UI.stop_timer(@timer)
          @timer = nil
        end
      end

      # Unregister all handlers for all files.
      def unregister_all
        @observers.clear
        if @timer
          UI.stop_timer(@timer)
          @timer = nil
        end
      end

      private

      def check_files
        @observers.each { |path, hash|
          begin
            exists = File.exist?(path)
            mtime = nil
            if exists # whether it exists now
              mtime = File.stat(path).mtime.to_i
              if !hash[:exists] # whether it existed before
                # File exists but did not exist before → created
                hash[:created].call(path) if hash[:created]
              else
                if hash[:mtime] < mtime
                  # File exists and existed before and the mtime differs → changed
                  hash[:changed].call(path) if hash[:changed]
                end
              end
            else
              # File does not exist but existed before → deleted
              hash[:deleted].call(path) if hash[:exists] && hash[:deleted]
            end
          rescue Exception => e
            ConsolePlugin.error(e)
          ensure
            hash[:exists] = exists
            hash[:mtime]  = mtime unless mtime.nil?
          end
        }
      end

    end # class FileObserver

  end # module ConsolePlugin

end # module AE
