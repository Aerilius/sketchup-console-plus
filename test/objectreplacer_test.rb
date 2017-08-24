require_relative 'test_helper'

module AE

  module ConsolePlugin

    require 'ae_console/object_replacer.rb'

    class TC_ObjectReplacer < TestCase

      class A
        @@cv = 1
        def initialize
          @iv = 1
          @mv = 1
        end
        attr_accessor :mv
      end

      def test_replace_global_variable
        old_value = 1
        new_value = 2
        $MY_GLOBAL_VARIABLE = old_value
        object_replacer = ObjectReplacer.new('$MY_GLOBAL_VARIABLE', new_value)
        assert_equal(old_value, $MY_GLOBAL_VARIABLE)
        object_replacer.enable
        assert_equal(new_value, $MY_GLOBAL_VARIABLE)
        object_replacer.disable
        assert_equal(old_value, $MY_GLOBAL_VARIABLE)
      end

      def test_replace_class_variable
        old_value = 1
        new_value = 2
        A.class_variable_set(:@@cv, old_value)
        
        object_replacer = ObjectReplacer.new('@@cv', new_value, A)
        assert_equal(old_value, A.class_variable_get(:@@cv))
        
        object_replacer.enable
        assert_equal(new_value, A.class_variable_get(:@@cv))
        
        object_replacer.disable
        assert_equal(old_value, A.class_variable_get(:@@cv))
      end

      def test_replace_instance_variable
        old_value = 1
        new_value = 2
        a = A.new
        a.instance_variable_set(:@iv, old_value)
        
        object_replacer = ObjectReplacer.new('@iv', new_value, a)
        assert_equal(old_value, a.instance_variable_get(:@iv))
        
        object_replacer.enable
        assert_equal(new_value, a.instance_variable_get(:@iv))
        
        object_replacer.disable
        assert_equal(old_value, a.instance_variable_get(:@iv))
      end

      def test_replace_accessor_method
        old_value = 1
        new_value = 2
        a = A.new
        a.instance_variable_set(:@mv, old_value)
        
        object_replacer = ObjectReplacer.new('mv', new_value, a)
        assert_equal(old_value, a.instance_variable_get(:@mv))
        assert_equal(old_value, a.mv)
        
        object_replacer.enable
        assert_equal(new_value, a.instance_variable_get(:@mv))
        assert_equal(new_value, a.mv)
        
        object_replacer.disable
        assert_equal(old_value, a.instance_variable_get(:@mv))
        assert_equal(old_value, a.mv)
      end

    end # class TC_ObjectReplacer

  end

end
