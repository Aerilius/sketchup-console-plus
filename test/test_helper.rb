# Add the source path if run from the console. 
# When run from SketchUp, this is the plugins load path.
if File.exists?(src_path = File.expand_path('../../src', __FILE__))
  $LOAD_PATH.unshift(src_path)
  # Now we could do: require 'ae_console'
end

module AE
  module ConsolePlugin

    if defined?(Sketchup)
      require 'testup/testcase'
      TestCase = TestUp::TestCase
    else
      require 'simplecov'
      SimpleCov.start
      require 'minitest'
      TestCase = Minitest::Test
      require 'minitest/autorun'
      PATH = File.expand_path('../../src/ae_console', __FILE__)
    end

  end
end
