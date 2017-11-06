require_relative 'test_helper' #require 'test_helper'
require_relative 'async_minitest_helper' #require 'async_minitest_helper'

module AE

  module ConsolePlugin

    require 'ae_console/features/fileobserver.rb'

    unless defined?(Sketchup)
      # Create a Mock for UI.start_timer.
      module UI
        @next_id = 0
        @threads = {}

        def self.start_timer(duration, repeat=false, &block)
          id = @next_id
          @next_id += 1
          if repeat
            @threads[id] = true
            @threads[id] = Thread.new{
              while @threads.include?(id)
                sleep(duration)
                block.call()
              end
            }
          else
            @threads[id] = Thread.new{
              sleep(duration)
              block.call()
            }
          end
          return id
        end

        def self.stop_timer(id)
          if @threads.include?(id)
            @threads[id].terminate
            @threads.delete(id)
          end
        end
      end # module UI
    end

    class TC_FileObserver < TestCase
      # This test suite fails when run in SketchUp because AsyncMiniTestHelper 
      # does not work with SketchUp's UI module's use of threading.

      def setup
        dir = File.dirname(__FILE__)
        @filename = File.join(dir, "test")
        @filename2 = File.join(dir, "test2")
        File.delete(@filename) if File.exists?(@filename)
        File.delete(@filename2) if File.exists?(@filename2)
        @observer = FileObserver.new(0.01)
      end

      def shutdown
        @observer.unregister_all
        @observer = nil
        File.delete(@filename) if File.exists?(@filename)
        File.delete(@filename2) if File.exists?(@filename2)
      end

      def test_created
        async = AsyncMiniTestHelper.new(self, 1)
        @observer.register(@filename, :created) { async.done() }

        File.open(@filename, "w"){ |f| f.puts("test") }
        async.await()
      end

      def test_changed
        async = AsyncMiniTestHelper.new(self, 2, 4.0)
        File.open(@filename, "w"){ |f| f.puts("test") }
        @observer.register(@filename, :changed) { async.done() }

        UI.start_timer(0.5, false) {
          File.open(@filename, "a"){ |f| f.puts("2") }
        }
        UI.start_timer(1.5, false) {
          File.open(@filename, "w"){ |f| f.puts("hello") }
        }
        async.await()
      end

      def test_deleted
        async = AsyncMiniTestHelper.new(self, 1)
        File.open(@filename, "w"){ |f| f.puts("test") }
        @observer.register(@filename, :deleted) { async.done() }
        UI.start_timer(0.5, false) {
          File.delete(@filename)
        }
        async.await()
      end

      def test_unregister
        async = AsyncMiniTestHelper.new(self, 1, 0.5)
        @observer.register(@filename, :created) { async.done() }
        @observer.register(@filename, :deleted) { async.done() }
        # Unregister a file with a specific event
        @observer.unregister(@filename, :created)
        File.open(@filename, "w"){ |f| f.puts("test") }
        async.await_timeout()

        # Other events for that file should still trigger
        async = AsyncMiniTestHelper.new(self, 1)
        File.delete(@filename)
        async.await()

        # Unregister all events for a file
        async = AsyncMiniTestHelper.new(self, 1, 0.5)
        @observer.unregister(@filename)
        async.await_timeout()
      end

      def test_unregister_all
        async = AsyncMiniTestHelper.new(self, 2, 0.5)
        @observer.register(@filename, :created) { async.done() }
        @observer.register(@filename2, :created) { async.done() }
        # Unregister all files
        @observer.unregister_all()
        File.open(@filename, "w"){ |f| f.puts("test") }
        File.open(@filename2, "w"){ |f| f.puts("test2") }
        async.await_timeout()
      end

    end # class TC_FileObserver

  end

end
