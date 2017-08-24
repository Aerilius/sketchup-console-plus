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
      # does not work with SketchUp's UI module's uses threading.

      def setup
        dir = File.dirname(__FILE__)
        @filename = File.join(dir, "test")
        File.delete(@filename) if File.exists?(@filename)
        @observer = FileObserver.new(0.2)
      end

      def shutdown
        @observer.unregister_all
        @observer = nil
        File.delete(@filename) if File.exists?(@filename)
      end

      def test_created
        async = AsyncMiniTestHelper.new(self, 1)
        @observer.register(@filename, :created) { async.done() }

        File.open(@filename, "w"){ |f| f.puts("test") }
        async.await()
      end

      def test_changed
        async = AsyncMiniTestHelper.new(self, 2, 3.0)
        File.open(@filename, "w"){ |f| f.puts("test") }
        @observer.register(@filename, :changed) { async.done() }

        UI.start_timer(1, false) {
          File.open(@filename, "a"){ |f| f.puts("2") }
        }
        UI.start_timer(2, false) {
          File.open(@filename, "w"){ |f| f.puts("hello") }
        }
        async.await()
      end

      def test_deleted
        async = AsyncMiniTestHelper.new(self, 1)
        File.open(@filename, "w"){ |f| f.puts("test") }
        @observer.register(@filename, :deleted) { async.done() }

        File.delete(@filename)
        async.await()
      end

    end # class TC_FileObserver

  end

end
