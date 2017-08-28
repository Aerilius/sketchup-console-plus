require_relative 'test_helper'

module AE

  module ConsolePlugin

    class TC_TokenResolver < TestCase

      require 'ae_console/features/tokenresolver.rb'

      def test_resolve_module_path
        actual = TokenResolver.resolve_module_path('ClassA::CONSTANT')
        assert_equal(ClassA::CONSTANT, actual, 'It should resolve a string of namespaces and constants into the constant')
        actual = TokenResolver.resolve_module_path('ClassA::ClassB')
        assert_equal(ClassA::ClassB, actual, 'It should resolve a string of namespaces and classes into the class')
        actual = TokenResolver.resolve_module_path('ClassA::ModuleB')
        assert_equal(ClassA::ModuleB, actual, 'It should resolve a string of namespaces and modules into the module')
      end

    end

    class TC_ForwardEvaluationResolver < TestCase

      require 'ae_console/features/tokenresolver.rb'

      def setup
        @original_docprovider = ConsolePlugin.const_get(:DocProvider)
        @docprovider = DocProviderStub.initialize
        ConsolePlugin.send(:const_set, :DocProvider, @docprovider)
      end

      def teardown
        ConsolePlugin.send(:const_set, :DocProvider, @original_docprovider)
      end

      def test_resolve_tokens
        binding = TOPLEVEL_BINDING

        # Given: token for existing object, second token for constant, method

        actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['ClassA', '::', 'CONSTANT'], binding)
        assert_equal('CONSTANT', actual.token)
        assert_equal(:constant,  actual.type)
        assert_equal('ClassA',   actual.namespace)

        actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['ClassA', 'ModuleB'], binding)
        assert_equal('ModuleB', actual.token)
        assert_equal(:module,   actual.type)
        assert_equal('ClassA',  actual.namespace)

        actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['ClassA', 'ClassB'], binding)
        assert_equal('ClassB', actual.token)
        assert_equal(:class,   actual.type)
        assert_equal('ClassA', actual.namespace)

        @docprovider.stub_data('ClassA.class_method_a', { :return => [['ClassE'], 'description'], :type => :class_method })
        actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['ClassA', '.', 'class_method_a'], binding)
        assert_equal('class_method_a', actual.token)
        assert_equal(:class_method,    actual.type)
        assert_equal('ClassA',         actual.namespace)

        @docprovider.stub_data('ClassA#instance_method_a', { :return => [['ClassF'], 'description'], :type => :instance_method })
        actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['INSTANCE_A', '.', 'instance_method_a'], binding)
        assert_equal('instance_method_a', actual.token)
        assert_equal(:instance_method,    actual.type)
        assert_equal('ClassA',            actual.namespace)

        # Given: third token
        @docprovider.stub_data('ClassA::ModuleB.module_function_b', { :return => [['ClassG'], 'description'], :type => :module_function })
        actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['ClassA', 'ModuleB', 'module_function_b'], binding)
        assert_equal('module_function_b', actual.token)
        assert_equal(:module_function,    actual.type)
        assert_equal('ClassA::ModuleB', actual.namespace)

        # Global method as token
        @docprovider.stub_data('Kernel.puts', { :return => [['NilClass'], 'description'], :type => :module_function })
        actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['puts'], binding)
        assert_equal('puts', actual.token)
        assert_equal(:module_function, actual.type)
        assert_equal('Kernel', actual.namespace)

        # Unresolvable token
        assert_raises(TokenResolver::TokenResolverError){
            actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['NonExistingConstant'], binding)
        }

        assert_raises(TokenResolver::TokenResolverError){
            actual = TokenResolver::ForwardEvaluationResolver.resolve_tokens(['ClassA', 'non_existing_method'], binding)
        }
      end

      def test_resolve_identifier_in_scope
        # Test different types of identifiers in different bindings.

        # top-level binding
        do_tests_for_identifiers_with_binding(TOPLEVEL_BINDING)
        # Top-level constants are inherited, hence we use a different constant for every test.
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, 'AE', TOPLEVEL_BINDING)
        assert_equal(::AE, actual.object)

        # Module binding
        binding = ModuleA::ModuleB::BINDING
        do_tests_for_identifiers_with_binding(binding)
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, 'TC_Autocompleter_CONSTANT1', binding)
        assert_equal(ModuleA::ModuleB::TC_Autocompleter_CONSTANT1, actual.object)

        # Class binding
        binding = ModuleA::ClassB::BINDING
        do_tests_for_identifiers_with_binding(binding)
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, 'TC_Autocompleter_CONSTANT2', binding)
        assert_equal(ModuleA::ClassB::TC_Autocompleter_CONSTANT2, actual.object)

        # instance binding
        a = ModuleA::ClassB.new
        binding = a.get_binding # send(:binding) considers module nesting from here!
        do_tests_for_identifiers_with_binding(binding)
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, 'TC_Autocompleter_CONSTANT2', binding)
        assert_equal(ModuleA::ClassB::TC_Autocompleter_CONSTANT2, actual.object)

        # local binding
        binding = a.test_local_binding
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, 'TC_Autocompleter_CONSTANT2', binding)
        assert_equal(ModuleA::ClassB::TC_Autocompleter_CONSTANT2, actual.object)
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, 'local_variable_b', binding) rescue nil
        assert_equal(42, actual.object)

        # method
        assert_raises(TokenResolver::TokenResolverError){
          TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, 'puts', binding)
        }
        assert_raises(TokenResolver::TokenResolverError){
          TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, 'unknown_token', binding)
        }
      end

      def do_tests_for_identifiers_with_binding(binding)
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, '$TC_Autocompleter_GLOBAL', binding)
        assert_equal($TC_Autocompleter_GLOBAL, actual.object)
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, '@tc_autocompleter_instance_variable', binding)
        assert_equal(binding.eval('@tc_autocompleter_instance_variable'), actual.object)
        actual = TokenResolver::ForwardEvaluationResolver.send(:resolve_identifier_in_scope, '@@tc_autocompleter_class_variable', binding)
        assert_equal(binding.eval('@@tc_autocompleter_class_variable'), actual.object)
      end

    end # class TC_ForwardEvaluationResolver

    class TC_BacktrackingResolver < TestCase

      require 'ae_console/features/tokenresolver.rb'

      def setup
        @original_docprovider = ConsolePlugin.const_get(:DocProvider)
        @docprovider = DocProviderStub.initialize # MiniTest::Mock.new
        ConsolePlugin.send(:const_set, :DocProvider, @docprovider)
      end

      def teardown
        ConsolePlugin.send(:const_set, :DocProvider, @original_docprovider)
      end

      def test_resolve_tokens
        # Mock @docprovider:
        @docprovider.initialize
        @docprovider.stub_data('ClassD#instance_method1', { :return => [['ClassA'], 'description'] })
        @docprovider.stub_data('ClassA#instance_method2', { :return => [['ClassE'], 'description'] })
        @docprovider.stub_data('ClassB#instance_method2', { :return => [['ClassF'], 'description'] })
        @docprovider.stub_data('ClassC#instance_method3', { :return => [['ClassG'], 'description'] })

        # Given: one token, token is available for classes A, B but not C
        actual = TokenResolver::BacktrackingResolver.resolve_tokens(['instance_method2'])
        assert_kind_of(MultipleTokenClassification, actual)
        namespaces = actual.classifications.map(&:namespace).sort
        assert_equal(['ClassA', 'ClassB'], namespaces)

        # Given: two tokens, second token is available for classes A, B but not C
        # first token produces class A but not B or C
        actual = TokenResolver::BacktrackingResolver.resolve_tokens(['instance_method1', 'instance_method2'])
        assert_equal('ClassA', actual.namespace)

        # Token has one match
        actual = TokenResolver::BacktrackingResolver.resolve_tokens(['instance_method3'])
        assert_equal('ClassC', actual.namespace)
        assert(!actual.is_a?(MultipleTokenClassification) || actual.classifications.length == 1)

        # Token has no matches
        assert_raises(TokenResolver::TokenResolverError){
          TokenResolver::BacktrackingResolver.resolve_tokens(['instance_method4'])
        }
      end

    end # class TC_BacktrackingResolver

    module DocProviderStub
      def self.initialize
        @apis = {}
        self
      end
      def self.stub_data(docpath, hash={})
        doc_info = {
        :description => 'Description Text',
        #:name => 'instance_method_b',
        #:namespace => 'ModuleA::ClassB',
        #:path => 'ModuleA::ClassB#instance_method_b',
        #:return => [['String', 'a string']],
        #:type => 'instance_method',
        :visibility => 'public'
        }.merge(hash)
        docpath[/^(?:(.*)(::|\.|#))?([^.:#]+)$/]
        doc_info[:name] = $3
        doc_info[:namespace] = ($1.nil?) ? '' : $1
        doc_info[:path] = docpath
        doc_info[:type] ||= ($2 == '#') ? :instance_method : raise # '.' :class_method, :module_function ; '::' :constant, :class, :module
        @apis[docpath.to_sym] = doc_info
        nil
      end
      def self.get_info_for_docpath(docpath)
        return @apis[docpath.to_sym]
      end
      def self.get_infos_for_docpath(docpath)
        return @apis.keys.select{ |key| key.to_s.index(docpath) == 0 }.map{ |key| @apis[key] }
      end
      def self.get_infos_for_token(token)
        return @apis.values.select{ |doc_info| doc_info[:name] == token }
      end
      def self.extract_return_types(doc_info)
        return doc_info[:return] && doc_info[:return].first || []
      end
    end # module DocProviderStub

  end

end

class ClassA
  CONSTANT ||= 42
  def self.class_method_a
  end
  def instance_method_a
  end
  module ModuleB
    def self.module_function_b
    end
  end
  module ModuleB1 # same methods as ModuleB
    def self.module_function_b
    end
  end
  module ModuleB2 # not same methods as ModuleB
  end
  class ClassB
    def self.class_method_b
    end
    def instance_method_b
    end
  end
end
INSTANCE_A ||= ClassA.new
class ClassA1 # same methods as ClassA
  CONSTANT ||= 42
  def self.class_method_a
  end
  def instance_method_a
  end
end
class ClassA2 # not same methods as ClassA
end

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
