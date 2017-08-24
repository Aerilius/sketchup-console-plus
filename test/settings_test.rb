require_relative 'test_helper'

module AE

  module ConsolePlugin

    require 'ae_console/settings.rb'

    if defined?(Sketchup)
      NATIVE = true
    else
      NATIVE = false

      # Create a Mock for read_defaults/write_defaults.
      module Sketchup
        @defaults = {}

        def self.read_default(section, key, value)
          @defaults[section] ||= {}
          value = @defaults[section].include?(key.to_s) ? @defaults[section][key.to_s] : value
          # Simulate SketchUp's incorrect string serialization.
          value = value.gsub(/\\\"/, '"').gsub(/\\\\/, '\\') if value.is_a?(String)
          return value
        end

        def self.write_default(section, key, value)
          @defaults[section] ||= {}
          @defaults[section][key.to_s] = value
          return true
        end

        def self.clear_defaults
          @defaults.clear
        end
      end
      class Length < Float; end
    end

    class TC_Settings < TestCase

      def setup
        # Cleanup the test data from the registry.
        if NATIVE
          # TODO: Implement proper cleaning for real Windows Registry or macOS plist files.
          ['key', 'key2', 'string', 'string1', 'float', 'fixnum', 'nil', 'boolean', 'array', 'array1', 'hash', 'hash1'].each{ |key|
            Sketchup.write_defaults('test', key, nil)
          }
        else
          Sketchup.clear_defaults
        end
      end

      def test_settings_load
        data = {'key' => 'value', 'key2' => 'value2'}
        name = 'key'
        expected = data[name]
        settings = Settings.new('test')
        property = settings.get_property('key2', 'default')
        property.add_listener('change'){ |triggered_value|
          assert_equal('value2', triggered_value, 'Loading settings should trigger the "change" event on overwritten properties.')
        }
        settings.load(data)
        actual = settings.get(name)
        assert_equal(expected, actual, 'It should return the loaded value.')
      end

      def settings_get
        data = {'key' => 'value', 'key2' => 'value2'}
        name = 'key'
        expected = data[name]
        settings = Settings.new('test').load(data)
        property = settings.get_property(name)
        assert_equal(expected, settings.get(name))
        assert_equal(expected, property.get_value())
        assert_equal(property.get_value(), settings.get(name))
      end

      def settings_set
        data = {'key5' => 'value', 'key2' => 'value2'}
        name = 'key5'
        expected_value = 'changed value'
        settings = Settings.new('test').load(data)
        property = settings.get_property(name)
        settings.add_listener('change'){ |triggered_name, triggered_value|
          assert_equal(name,           triggered_name,  'settings.set should trigger "changed" on settings')
          assert_equal(expected_value, triggered_value, 'settings.set should trigger "changed" on settings')
        }
        property.add_listener('change'){ |triggered_value|
          assert_equal(expected_value, triggered_value, 'settings.set should trigger "changed" on property')
        }
        settings.set(name, expected_value)
        assert_equal(expected_value, settings.get(name))
        assert_equal(expected_value, property.get_value())
      end

      def test_property_set_value
        data = {'key' => 'value3', 'key2' => 'value2'}
        name = 'key'
        expected_value = 'changed value3'
        settings = Settings.new('test').load(data)
        property = settings.get_property(name)
        settings.add_listener('change'){ |triggered_name, triggered_value|
          assert_equal(name,           triggered_name,  'property.set_value should trigger "changed" on settings')
          assert_equal(expected_value, triggered_value, 'property.set_value should trigger "changed" on settings')
        }
        property.add_listener('change'){ |triggered_value|
          assert_equal(expected_value, triggered_value, 'property.set_value should trigger "changed"')
        }
        property.set_value(expected_value)
        assert_equal(expected_value, settings.get(name))
        assert_equal(expected_value, property.get_value())
      end

      def test_supported_types
        data0 = {
          'string'  => 'string1',
          'string1' => '"', # Sketchup's original write_default writes """
          'float'   => 3.14,
          'fixnum'  => 2,
          'nil'     => nil,
          'boolean' => false,
          'array'   => ['a',2,3.14,false,[],['a'],{'key'=>'value'}],
          'array1'  => [nil], # Sketchup's original write_default writes []
          'hash'    => {'key' => 'value'},
          'hash1'   => {'key' => 'value'}
        }
        data = {
          'string'  => 'string2',
          'string1' => '"',
          'float'   => 7.23,
          'fixnum'  => 3,
          'nil'     => nil,
          'boolean' => true,
          'array'   => ['b',3,7.23,true,[],['b'],{'key2'=>'value2'}],
          'array1'  => [nil],
          'hash'    => {'key2' => 'value2'},
          'hash1'   => {'key2' => nil}
        }
        # Load initial data with default values.
        settings1 = Settings.new('test').load(data0)
        #data1.each{ |key, value| settings1[key] = 'x' }
        # Assign new values to trigger writing to registry.
        data.each{ |key, value|
          settings1[key] = value
          if value.nil?
            assert_nil(settings1[key], "Failed to accept #{value.class}")
          else
            assert_equal(value, settings1[key], "Failed to accept #{value.class}")
          end
        }
        # The registry should now contain values from `data`.
        # Test whether data was written to the registry and whether it was read correctly.
        settings2 = Settings.new('test')
        # Load initial data with default values. If keys have corresponding values in registry, they will be loaded instead.
        settings2.load(data0)
        data.each{ |key, expected_value|
          if expected_value.nil?
            assert_nil(settings1[key], "Failed to write or read #{expected_value.class}")
          else
            assert_equal(expected_value, settings1[key], "Failed to write or read #{expected_value.class}")
          end
        }
      end

    end # class TC_Settings

  end

end
