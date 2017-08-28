# Add the source path if run from the console. 
# When run from SketchUp, this is the plugins load path.
if File.exists?(src_path = File.expand_path('../../src', __FILE__))
  $LOAD_PATH.unshift(src_path)
  # Now we could do: require 'ae_console'
end

# Do not display warnings
$VERBOSE = false

# Define namespaces
# and choose TestCase class depending on environment.
module AE
  module ConsolePlugin

    if defined?(Sketchup)
      require 'testup/testcase'
      TestCase = TestUp::TestCase
    else
      begin
        require 'simplecov'
        SimpleCov.start
      rescue LoadError
      end
      require 'minitest'
      TestCase = Minitest::Test
      require 'minitest/autorun'
      PATH = File.expand_path('../../src/ae_console', __FILE__)
    end

  end
end
