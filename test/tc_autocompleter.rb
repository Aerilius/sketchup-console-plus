module AE

  module ConsolePlugin

    PATH = File.join(File.dirname(File.dirname(File.expand_path(__FILE__))), 'src', 'ae_console')

    require '../src/ae_console/features/autocompleter.rb'

    if defined?(Sketchup)
      require 'testup/testcase'
      TestCase = TestUp::TestCase
    else
      require 'minitest'
      TestCase = Minitest::Test
      require 'minitest/autorun'
    end

    module DocProvider # Mock
      def self.initialize
        @apis = {}
        nil
      end
      def self.apis
        return @apis
      end
      def self.get_api_info(doc_path)
        return @apis[doc_path.to_sym]
      end
      def self.get_api_infos(doc_path)
        return @apis.keys.select{ |key| key.to_s.index(doc_path) == 0 }.map{ |key| @apis[key] }
      end
    end

    class TC_Autocompleter < TestCase

      def setup
        DocProvider.initialize
      end

      def test_resolve_identifier_in_scope
        # top-level binding
        do_tests_for_identifiers_with_binding(TOPLEVEL_BINDING)
        # Top-level constants are inherited, hence we use a different constant for every test.
        result = Autocompleter.send(:resolve_identifier_in_scope, 'AE', TOPLEVEL_BINDING)
        assert_equal(::AE, result.object)
        # Module binding
        binding = ModuleA::ModuleB::BINDING
        do_tests_for_identifiers_with_binding(binding)
        result = Autocompleter.send(:resolve_identifier_in_scope, 'TC_Autocompleter_CONSTANT1', binding)
        assert_equal(ModuleA::ModuleB::TC_Autocompleter_CONSTANT1, result.object)
        # Class binding
        binding = ModuleA::ClassB::BINDING
        do_tests_for_identifiers_with_binding(binding)
        result = Autocompleter.send(:resolve_identifier_in_scope, 'TC_Autocompleter_CONSTANT2', binding)
        assert_equal(ModuleA::ClassB::TC_Autocompleter_CONSTANT2, result.object)
        # instance binding
        a = ModuleA::ClassB.new
        binding = a.get_binding # send(:binding) considers module nesting from here!
        do_tests_for_identifiers_with_binding(binding)
        result = Autocompleter.send(:resolve_identifier_in_scope, 'TC_Autocompleter_CONSTANT2', binding)
        assert_equal(ModuleA::ClassB::TC_Autocompleter_CONSTANT2, result.object)
        # local binding
        binding = a.test_local_binding
        result = Autocompleter.send(:resolve_identifier_in_scope, 'TC_Autocompleter_CONSTANT2', binding)
        assert_equal(ModuleA::ClassB::TC_Autocompleter_CONSTANT2, result.object)
        result = Autocompleter.send(:resolve_identifier_in_scope, 'local_variable_b', binding) rescue nil
        assert_equal(42, result) # fails: We cannot yet look up local variables.
      end

      def do_tests_for_identifiers_with_binding(binding)
        result = Autocompleter.send(:resolve_identifier_in_scope, '$TC_Autocompleter_GLOBAL', binding)
        assert_equal($TC_Autocompleter_GLOBAL, result.object)
        result = Autocompleter.send(:resolve_identifier_in_scope, '@tc_autocompleter_instance_variable', binding)
        assert_equal(binding.eval('@tc_autocompleter_instance_variable'), result.object)
        result = Autocompleter.send(:resolve_identifier_in_scope, '@@tc_autocompleter_class_variable', binding)
        assert_equal(binding.eval('@@tc_autocompleter_class_variable'), result.object)
      end

      def test_token_classification_by_object
        # Creating a classification for an instance
        object = ModuleA::ClassB.new
        classification = Autocompleter::TokenClassificationByObject.new('new', :class_method, 'ModuleA::ClassB', object)
        assert(classification.doc_path, 'ModuleA::ClassB.new')
        assert_equal(object, classification.instance_variable_get(:@returned_object))
        # Getting completions
        do_tests_for_completions(classification)
        # Resolving an instance method
        result = do_tests_for_instance_method(classification)
        if result.is_a?(Autocompleter::TokenClassificationByDoc)
          #assert(result.is_a?(Autocompleter::TokenClassificationByDoc), result.class.name)
          assert_equal('String', result.instance_variable_get(:@returned_class_path))
        else
          assert_kind_of(Autocompleter::TokenClassificationByClass, result)
          assert_equal(String, result.instance_variable_get(:@returned_class))
        end
        # Resolving a class method
        classification = Autocompleter::TokenClassificationByObject.new('ClassB', :constant, 'ModuleA', ModuleA::ClassB)
        result = do_tests_for_class_method(classification)
        if result.is_a?(Autocompleter::TokenClassificationByDoc)
          #assert(result.is_a?(Autocompleter::TokenClassificationByDoc), result.class.name)
          assert_equal('String', result.instance_variable_get(:@returned_class_path))
        else
          assert_kind_of(Autocompleter::TokenClassificationByClass, result)
          assert_equal(String, result.instance_variable_get(:@returned_class))
        end
        # Resolving a Module
        classification = Autocompleter::TokenClassificationByObject.new('ModuleA', :constant, '', ModuleA)
        result = do_tests_for_module(classification)
        assert_kind_of(Autocompleter::TokenClassificationByObject, result)
        assert_equal(ModuleA::ModuleB, result.instance_variable_get(:@returned_object))
        # Resolving a Class
        classification = Autocompleter::TokenClassificationByObject.new('ModuleA', :constant, '', ModuleA)
        result = do_tests_for_class(classification)
        assert_kind_of(Autocompleter::TokenClassificationByObject, result)
        assert_equal(ModuleA::ClassB, result.instance_variable_get(:@returned_object))
        # Resolving a constructor method
        classification = Autocompleter::TokenClassificationByObject.new('ClassB', :constant, 'ModuleA', ModuleA::ClassB)
        result = do_tests_for_constructor_method(classification)
        assert_equal(ModuleA::ClassB, result.instance_variable_get(:@returned_class))
        assert_equal(true, result.instance_variable_get(:@is_instance))
      end

      def test_token_classification_by_class
        # Creating a classification for a class/module
        klass = ModuleA::ClassB
        classification = Autocompleter::TokenClassificationByClass.new('new', :class_method, 'ModuleA::ClassB', klass, true)
        assert(classification.doc_path, 'ModuleA::ClassB.new')
        assert_equal(klass, classification.instance_variable_get(:@returned_class))
        assert_equal(true, classification.instance_variable_get(:@is_instance))
        # Getting completions
        do_tests_for_completions(classification)
        # Resolving an instance method
        result = do_tests_for_instance_method(classification)
        if result.is_a?(Autocompleter::TokenClassificationByDoc)
          #assert(result.is_a?(Autocompleter::TokenClassificationByDoc), result.class.name)
          assert_equal('String', result.instance_variable_get(:@returned_class_path))
        else
          assert_kind_of(Autocompleter::TokenClassificationByClass, result)
          assert_equal(String, result.instance_variable_get(:@returned_class))
        end
        # Resolving a class method
        classification = Autocompleter::TokenClassificationByClass.new('ClassB', :constant, 'ModuleA', ModuleA::ClassB, false)
        result = do_tests_for_class_method(classification)
        if result.is_a?(Autocompleter::TokenClassificationByDoc)
          #assert(result.is_a?(Autocompleter::TokenClassificationByDoc), result.class.name)
          assert_equal('String', result.instance_variable_get(:@returned_class_path))
        else
          assert_kind_of(Autocompleter::TokenClassificationByClass, result)
          assert_equal(String, result.instance_variable_get(:@returned_class))
        end
        # Resolving a Module
        classification = Autocompleter::TokenClassificationByClass.new('ModuleA', :constant, '', ModuleA, false)
        result = do_tests_for_module(classification)
        assert_kind_of(Autocompleter::TokenClassificationByClass, result)
        assert_equal(ModuleA::ModuleB, result.instance_variable_get(:@returned_class))
        # Resolving a Class
        classification = Autocompleter::TokenClassificationByClass.new('ModuleA', :constant, '', ModuleA, false)
        result = do_tests_for_class(classification)
        assert_kind_of(Autocompleter::TokenClassificationByClass, result)
        assert_equal(ModuleA::ClassB, result.instance_variable_get(:@returned_class))
        # Resolving a constructor method
        classification = Autocompleter::TokenClassificationByClass.new('ClassB', :constant, 'ModuleA', ModuleA::ClassB, false)
        result = do_tests_for_constructor_method(classification)
        assert_kind_of(Autocompleter::TokenClassificationByClass, result)
        assert_equal('ModuleA::ClassB.new', result.doc_path)
        assert_equal(ModuleA::ClassB, result.instance_variable_get(:@returned_class))
        assert_equal(true, result.instance_variable_get(:@is_instance))
      end

      def test_token_classification_by_doc
        # Creating a classification for an instance of a class
        classification = Autocompleter::TokenClassificationByDoc.new('new', :class_method, 'ModuleA::ClassB', 'ModuleA::ClassB', true)
        assert(classification.doc_path, 'ModuleA::ClassB.new')
        assert_equal('ModuleA::ClassB', classification.instance_variable_get(:@returned_class_path))
        assert_equal(true, classification.instance_variable_get(:@is_instance))
        # Getting completions
        DocProvider.apis[:'ModuleA::ClassB#instance_method_b'] = {:description => 'Description Text', :name => 'instance_method_b', :namespace => 'ModuleA::ClassB', :path => 'ModuleA::ClassB#instance_method_b', :return => ['String', 'a string'], :type => 'instance_method', :visibility => 'public'}
        DocProvider.apis[:'ModuleA::ClassB#other_instance_method_b'] = {:description => 'Description Text', :name => 'other_instance_method_b', :namespace => 'ModuleA::ClassB', :path => 'ModuleA::ClassB#other_instance_method_b', :return => ['nil', ''], :type => 'instance_method', :visibility => 'public'}
        do_tests_for_completions(classification)
        # Resolving an instance method
        result = do_tests_for_instance_method(classification)
        if result.is_a?(Autocompleter::TokenClassificationByDoc)
          #assert(result.is_a?(Autocompleter::TokenClassificationByDoc), result.class.name)
          assert_equal('String', result.instance_variable_get(:@returned_class_path))
        else
          assert_kind_of(Autocompleter::TokenClassificationByClass, result)
          assert_equal(String, result.instance_variable_get(:@returned_class))
        end
        # Resolving a class method
        classification = Autocompleter::TokenClassificationByClass.new('ClassB', :constant, 'ModuleA', ModuleA::ClassB, false)
        result = do_tests_for_class_method(classification)
        if result.is_a?(Autocompleter::TokenClassificationByDoc)
          #assert(result.is_a?(Autocompleter::TokenClassificationByDoc), result.class.name)
          assert_equal('String', result.instance_variable_get(:@returned_class_path))
        else
          assert_kind_of(Autocompleter::TokenClassificationByClass, result)
          assert_equal(String, result.instance_variable_get(:@returned_class))
        end
        # Resolving a Module
        classification = Autocompleter::TokenClassificationByClass.new('ModuleA', :constant, '', ModuleA, false)
        result = do_tests_for_module(classification)
        assert_kind_of(Autocompleter::TokenClassificationByClass, result)
        assert_equal(ModuleA::ModuleB, result.instance_variable_get(:@returned_class))
        # Resolving a Class
        classification = Autocompleter::TokenClassificationByClass.new('ModuleA', :constant, '', ModuleA, false)
        result = do_tests_for_class(classification)
        assert_kind_of(Autocompleter::TokenClassificationByClass, result)
        assert_equal(ModuleA::ClassB, result.instance_variable_get(:@returned_class ))
        # Resolving a constructor method
        classification = Autocompleter::TokenClassificationByClass.new('ClassB', :constant, 'ModuleA', ModuleA::ClassB, false)
        result = do_tests_for_constructor_method(classification)
        assert_equal(ModuleA::ClassB, result.instance_variable_get(:@returned_class))
        assert_equal(true, result.instance_variable_get(:@is_instance))
      end

      def do_tests_for_completions(classification)
        completions1 = classification.get_completions('')
        completions2 = classification.get_completions('in')
        completions3 = classification.get_completions('x')
        assert(completions1.find{ |c| c.token.to_s == 'instance_method_b' })
        assert(completions1.find{ |c| c.token.to_s == 'other_instance_method_b' })
        assert(completions2.find{ |c| c.token.to_s == 'instance_method_b' })
        assert(completions3.empty?, completions3.inspect)
      end

      def do_tests_for_instance_method(classification)
        DocProvider.apis[:'ModuleA::ClassB#instance_method_b'] = {:description => 'Description Text', :name => 'instance_method_b', :namespace => 'ModuleA::ClassB', :path => 'ModuleA::ClassB#instance_method_b', :return => ['String', 'a string'], :type => 'instance_method', :visibility => 'public'}
        result = classification.resolve('instance_method_b')
        assert_equal('instance_method_b', result.token)
        assert_equal(:instance_method, result.type)
        assert_equal('ModuleA::ClassB', result.class_path)
        assert_equal('ModuleA::ClassB#instance_method_b', result.doc_path)
        return result
      end

      def do_tests_for_class_method(classification)
        DocProvider.apis[:'ModuleA::ClassB.class_method_b'] = {:description => 'Description Text', :name => 'class_method_b', :namespace => 'ModuleA::ClassB', :path => 'ModuleA::ClassB.class_method_b', :return => ['String', 'a string'], :type => 'class_method', :visibility => 'public'}
        result = classification.resolve('class_method_b')
        assert_equal('class_method_b', result.token)
        assert_equal(:class_method, result.type)
        assert_equal('ModuleA::ClassB', result.class_path)
        assert_equal('ModuleA::ClassB.class_method_b', result.doc_path)
        return result
      end

      def do_tests_for_module(classification)
        result = classification.resolve('ModuleB')
        assert_equal('ModuleB', result.token)
        assert_equal(:module, result.type)
        assert_equal('ModuleA', result.class_path)
        assert_equal('ModuleA::ModuleB', result.doc_path)
        return result
      end

      def do_tests_for_class(classification)
        result = classification.resolve('ClassB')
        assert_equal('ClassB', result.token)
        assert_equal(:class, result.type)
        assert_equal('ModuleA', result.class_path)
        assert_equal('ModuleA::ClassB', result.doc_path)
        return result
      end

      def do_tests_for_constructor_method(classification)
        result = classification.resolve('new')
        assert_equal('new', result.token)
        assert_equal(:class_method, result.type)
        assert_equal('ModuleA::ClassB', result.class_path)
        assert_kind_of(Autocompleter::TokenClassificationByClass, result)
        assert_equal('ModuleA::ClassB.new', result.doc_path)
        return result
      end
    end

  end # class ConsolePlugin

end # module AE

$TC_Autocompleter_GLOBAL = true
@tc_autocompleter_instance_variable = 11
@@tc_autocompleter_class_variable = 12
module ModuleA
  module ModuleB
    BINDING = binding
    TC_Autocompleter_CONSTANT1 = 20
    @tc_autocompleter_instance_variable = 21
    @@tc_autocompleter_class_variable = 22
    def self.module_method_b
      return 'string'
    end
  end
  class ClassB
    BINDING = binding
    TC_Autocompleter_CONSTANT2 = 30
    @tc_autocompleter_instance_variable = 31
    @@tc_autocompleter_class_variable = 32
    def self.class_method_b
    end
    def initialize
      @tc_autocompleter_instance_variable = 41
    end
    def instance_method_b
      return 'string'
    end
    def other_instance_method_b
    end
    def get_binding
      return binding
    end
    def test_local_binding
      local_variable_b = 42
      return binding
    end
  end
  def self.module_method_a
    return ClassB.new
  end
  CONSTANT_FIXNUM = 1
  CONSTANT_B = ClassB.new
end
