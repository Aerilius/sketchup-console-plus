require_relative 'test_helper'

module AE

  module ConsolePlugin

    class TC_TokenClassification < TestCase

      # Test-matrix:
      #
      #   every subclass of TokenClassification  [test_token_classification_by_object…]
      # × representing different types of tokens [class, module, instance]
      # × resolve with different tokens          [CONSTANT, Class, Module, method, new-constructor]

      require 'ae_console/features/tokenclassification.rb'

      def setup
        @original_docprovider = ConsolePlugin.const_get(:DocProvider)
        @docprovider = DocProviderStub.initialize
        ConsolePlugin.send(:const_set, :DocProvider, @docprovider)
        
        # Mock @docprovider:
        @docprovider.initialize
        @docprovider.stub_data('ClassA#instance_method_a', { :return => [['ClassC'], 'description'] })
        @docprovider.stub_data('ClassA.class_method_a', { :return => [['ClassC'], 'description'], :type => :class_method })
        @docprovider.stub_data('ClassA.new', { :return => [['ClassA'], 'description'], :type => :class_method })
        @docprovider.stub_data('ClassA1#instance_method_a', { :return => [['ClassC'], 'description'] })
        @docprovider.stub_data('ClassA1.class_method_a', { :return => [['ClassC'], 'description'], :type => :class_method })
        @docprovider.stub_data('ClassA::ModuleB.module_function_b', { :return => [['ClassC'], 'description'], :type => :module_function })
        @docprovider.stub_data('ClassA::ModuleB1.module_function_b', { :return => [['ClassC'], 'description'], :type => :module_function })
        @docprovider.stub_data('ClassC#returns_different_types', { :return => [['ClassA', 'ClassB', 'ClassC'], 'description'], :type => :module_function })
      end

      def teardown
        ConsolePlugin.send(:const_set, :DocProvider, @original_docprovider)
      end

      def test_docpath
        d = 'The docpath of a toplevel module should be the module name'
        actual = TokenClassification.new('ModuleName', :module, '', 0).docpath
        assert_equal('ModuleName', actual, d)
        actual = TokenClassification.new('ClassName', :class, '', 0).docpath
        assert_equal('ClassName', actual, d)
        actual = TokenClassification.new('TOPLEVEL_CONSTANT', :constant, '', 0).docpath
        assert_equal('TOPLEVEL_CONSTANT', actual, d)

        d = 'The docpath of a module should be the separated by "::"'
        actual = TokenClassification.new('ModuleName', :module, 'Namespace', 0).docpath
        assert_equal('Namespace::ModuleName', actual, d)
        actual = TokenClassification.new('ClassName', :class, 'Namespace', 0).docpath
        assert_equal('Namespace::ClassName', actual, d)
        actual = TokenClassification.new('CONSTANT_NAME', :constant, 'Namespace', 0).docpath
        assert_equal('Namespace::CONSTANT_NAME', actual, d)

        d = 'The docpath of a class should be the separated by "."'
        actual = TokenClassification.new('module_function_name', :module_function, 'ModuleName', 0).docpath
        assert_equal('ModuleName.module_function_name', actual, d)
        actual = TokenClassification.new('class_method_name', :class_method, 'ClassName', 0).docpath
        assert_equal('ClassName.class_method_name', actual, d)
        actual = TokenClassification.new('instance_method_name', :instance_method, 'ClassName', 0).docpath
        assert_equal('ClassName#instance_method_name', actual, d)
      end

      def test_token_classification_by_object
        classification = TokenClassificationByObject.new('ClassA', :class, '', 0, ClassA)
        do_resolve_on_a_class(classification)
        do_get_completions(classification)

        classification = TokenClassificationByObject.new('ModuleB', :module, 'ClassA', 0, ClassA::ModuleB)
        do_resolve_on_a_module(classification)

        classification = TokenClassificationByObject.new('object', :local_variable, 'ClassA', 0, ClassA.new)
        do_resolve_on_an_instance(classification)
        do_get_completions(classification)
      end

      def test_token_classification_by_class
        classification = TokenClassificationByClass.new('ClassA', :class, '', 0, ClassA, false)
        do_resolve_on_a_class(classification)
        do_get_completions(classification)
        
        classification = TokenClassificationByClass.new('ModuleB', :module, 'ClassA', 0, ClassA::ModuleB, false)
        do_resolve_on_a_module(classification)
        
        classification = TokenClassificationByClass.new('ClassA', :local_variable, '', 0, ClassA, true)
        do_resolve_on_an_instance(classification)
        do_get_completions(classification)
      end

      def test_token_classification_by_doc
        original_class_a = ClassA
        Object.send(:remove_const, :ClassA)
        # Add mocks for @docprovider:
        @docprovider.stub_data('ClassA::CONSTANT', { :return => [['Integer'], 'description'], :type => :constant })
        @docprovider.stub_data('ClassA::ModuleB', { :return => [['ClassA::ModuleB'], 'description'], :type => :module })
        @docprovider.stub_data('ClassA::ClassB', { :return => [['ClassA::ClassB'], 'description'], :type => :class })
        @docprovider.stub_data('ClassA::XX', { :return => [['ClassA::XX'], 'description'], :type => :constant })
        @docprovider.stub_data('ClassA::XY', { :return => [['ClassA::XY'], 'description'], :type => :class })
        @docprovider.stub_data('ClassA::XZ', { :return => [['ClassA::XZ'], 'description'], :type => :module })
        @docprovider.stub_data('ClassA.xx', { :return => [['ClassD'], 'description'], :type => :class_method })
        @docprovider.stub_data('ClassA.xy', { :return => [['ClassD'], 'description'], :type => :class_method })
        @docprovider.stub_data('ClassA.xz', { :return => [['ClassD'], 'description'], :type => :class_method })
        @docprovider.stub_data('ClassA#yx', { :return => [['ClassD'], 'description'], :type => :instance_method })
        @docprovider.stub_data('ClassA#yy', { :return => [['ClassD'], 'description'], :type => :instance_method })
        @docprovider.stub_data('ClassA#yz', { :return => [['ClassD'], 'description'], :type => :instance_method })

        classification = TokenClassificationByDoc.new('ClassA', :class, '', 0, 'ClassA', false)
        do_resolve_on_a_class(classification)
        do_get_completions(classification)

        classification = TokenClassificationByDoc.new('ModuleB', :module, 'ClassA', 0, 'ClassA::ModuleB', false)
        do_resolve_on_a_module(classification)

        classification = TokenClassificationByDoc.new('ClassA', :class, '', 0, 'ClassA', true)
        do_resolve_on_an_instance(classification)
        do_get_completions(classification)

        Object.const_set(:ClassA, original_class_a)
      end

      def test_multiple_token_classification
        class_a  = TokenClassificationByObject.new('ClassA', :class, '', 0, ClassA)
        class_a1 = TokenClassificationByObject.new('ClassA', :class, '', 0, ClassA1)
        class_a2 = TokenClassificationByObject.new('ClassA', :class, '', 0, ClassA2)
        module_b  = TokenClassificationByObject.new('ModuleB', :module, 'ClassA', 0, ClassA::ModuleB)
        module_b1 = TokenClassificationByObject.new('ModuleB', :module, 'ClassA', 0, ClassA::ModuleB1)
        module_b2 = TokenClassificationByObject.new('ModuleB', :module, 'ClassA', 0, ClassA::ModuleB2)
        instance_a  = TokenClassificationByObject.new('object', :local_variable, '', 0, ClassA.new)
        instance_a1 = TokenClassificationByObject.new('object', :local_variable, '', 0, ClassA1.new)
        instance_a2 = TokenClassificationByObject.new('object', :local_variable, '', 0, ClassA2.new)

        # Multiple classifications of which only one resolves the given token
        d = 'A MultipleTokenClassification of two classes should resolve to a single classification if only one matches the token'
        classification = MultipleTokenClassification.new([class_a, class_a2])
        actual = classification.resolve('class_method_a')
        assert(!actual.is_a?(MultipleTokenClassification) || actual.classifications.length == 1, d)

        d = 'A MultipleTokenClassification of two modules should resolve to a single classification if only one matches the token'
        classification = MultipleTokenClassification.new([module_b, module_b2])
        actual = classification.resolve('module_function_b')
        assert(!actual.is_a?(MultipleTokenClassification) || actual.classifications.length == 1, d)

        d = 'A MultipleTokenClassification of two instances should resolve to a single classification if only one matches the token'
        classification = MultipleTokenClassification.new([instance_a, instance_a2])
        actual = classification.resolve('instance_method_a')
        assert(!actual.is_a?(MultipleTokenClassification) || actual.classifications.length == 1, d)

        # Multiple classifications of which two resolve the given token
        d = 'A MultipleTokenClassification of classes should resolve to as many classification as there match to the token'
        classification = MultipleTokenClassification.new([class_a, class_a1, class_a2])
        actual = classification.resolve('class_method_a')
        assert_kind_of(MultipleTokenClassification, actual, d)
        assert_equal(2, actual.classifications.length, d)

        d = 'A MultipleTokenClassification of modules should resolve to as many classification as there match to the token'
        classification = MultipleTokenClassification.new([module_b, module_b1, module_b2])
        actual = classification.resolve('module_function_b')
        assert_kind_of(MultipleTokenClassification, actual, d)
        assert_equal(2, actual.classifications.length, d)

        d = 'A MultipleTokenClassification of instances should resolve to as many classification as there match to the token'
        classification = MultipleTokenClassification.new([instance_a, instance_a1, instance_a2])
        actual = classification.resolve('instance_method_a')
        assert_kind_of(MultipleTokenClassification, actual, d)
        assert_equal(2, actual.classifications.length, d)

        d = 'It should raise for an unresolvable token'
        classification = MultipleTokenClassification.new([instance_a, instance_a1, instance_a2])
        assert_raises(TokenClassification::TokenNotResolvedError){
          classification.resolve('non_existing_method')
        }

        # Normal classification with method that returns multiple types, should resolve to MultipleTokenClassification
        d = 'Resolving a method that can return multiple types should return a MultipleTokenClassification'
        classification = TokenClassificationByDoc.new('object', :local_variable, '', 0, 'ClassC', true)
        actual = classification.resolve('returns_different_types')
        assert_kind_of(MultipleTokenClassification, actual, d)
        assert_equal(3, actual.classifications.length, d)

        # A multiple token classification of which one token resolves again to a multiple token classification
        d = 'Resolved classifications and MultipleTokenClassifications should be flattened'
        classification = TokenClassificationByDoc.new('object', :local_variable, '', 0, 'ClassC', true)
        classification = MultipleTokenClassification.new([classification])
        actual = classification.resolve('returns_different_types')
        assert_kind_of(MultipleTokenClassification, actual, d)
        # actual.classifications does not contain MultipleTokenClassifications
        assert_equal(3, actual.classifications.length, d)
        assert_equal(0, actual.classifications.grep(MultipleTokenClassification).length, d)

        # Get completions
        classification = MultipleTokenClassification.new([class_a, class_a2])
        do_get_completions(classification)
      end

      def do_get_completions(classification)
        if classification.type == :class || classification.type == :module
          actual = classification.get_completions('x')
          puts actual.inspect
          assert_equal(3, actual.length, "It should return all matching methods (#{caller.first})")
          assert(actual.all?{ |c| c.type == :class_method }, "The completions should have the correct type (#{caller.first})")

          actual = classification.get_completions('X')
          assert_equal(3, actual.length, "It should return all matching constants')
          assert(actual.find{ |c| c.type == :constant }, 'The completions should have the correct type (#{caller.first})")
          assert(actual.find{ |c| c.type == :class }, "The completions should have the correct type (#{caller.first})")
          assert(actual.find{ |c| c.type == :module }, "The completions should have the correct type (#{caller.first})")
        else
          actual = classification.get_completions('y')
          puts actual.inspect
          assert_equal(3, actual.length, "It should return all matching methods (#{caller.first})")
          assert(actual.all?{ |c| c.type == :instance_method }, "The completions should have the correct type (#{caller.first})")
        end
      end

      def do_resolve_on_a_class(classification)
        # constant
        d = "A #{classification.class} of a class should resolve a constant (#{caller.first})"
        actual = classification.resolve('CONSTANT')
        assert_equal('CONSTANT', actual.token, d)
        assert_equal(:constant, actual.type, d)
        assert_equal('ClassA', actual.namespace, d) # TODO: depends on given classification!

        # module
        d = "A #{classification.class} of a class should resolve a contained module (#{caller.first})"
        actual = classification.resolve('ModuleB')
        assert_equal('ModuleB', actual.token, d)
        assert_equal(:module, actual.type, d)
        assert_equal('ClassA', actual.namespace, d)

        # class
        d = "A #{classification.class} of a class should resolve a contained class (#{caller.first})"
        actual = classification.resolve('ClassB')
        assert_equal('ClassB', actual.token, d)
        assert_equal(:class, actual.type, d)
        assert_equal('ClassA', actual.namespace, d)

        # class method
        d = "A #{classification.class} of a class should resolve an class method (#{caller.first})"
        actual = classification.resolve('class_method_a')
        assert_equal('class_method_a', actual.token, d)
        assert_equal(:class_method, actual.type, d)
        assert_equal('ClassA', actual.namespace, d)

        # class method new
        d = "A #{classification.class} of a class should resolve a 'new' to an instance of itself (#{caller.first})"
        actual = classification.resolve('new')
        assert_equal('new', actual.token, d)
        assert_equal(:class_method, actual.type, d)
        assert_equal('ClassA', actual.namespace, d)
        assert(actual.is_a?(TokenClassificationByClass) || actual.is_a?(TokenClassificationByDoc))
        assert(actual.instance_variable_get(:@is_instance), d)
      end

      def do_resolve_on_a_module(classification)
        # module method
        d = "A #{classification.class} of a module should resolve a module function (#{caller.first})"
        actual = classification.resolve('module_function_b')
        assert_equal('module_function_b', actual.token, d)
        assert_equal(:module_function, actual.type, d)
        assert_equal('ClassA::ModuleB', actual.namespace, d)
      end

      def do_resolve_on_an_instance(classification)
        # instance method
        d = "A #{classification.class} of an instance should resolve an instance method (#{caller.first})"
        actual = classification.resolve('instance_method_a')
        assert_equal('instance_method_a', actual.token, d)
        assert_equal(:instance_method, actual.type, d)
        assert_equal('ClassA', actual.namespace, d)
      end

=begin
      # TODO:
      def do_tests_for_completions(classification)
        completions1 = classification.get_completions('')
        completions2 = classification.get_completions('in')
        completions3 = classification.get_completions('x')
        assert(completions1.find{ |c| c.token.to_s == 'instance_method_b' })
        assert(completions1.find{ |c| c.token.to_s == 'other_instance_method_b' })
        assert(completions2.find{ |c| c.token.to_s == 'instance_method_b' })
        assert(completions3.empty?, completions3.inspect)
      end
=end

    end # class TC_TokenClassification

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
      def self.get_infos_for_docpath_prefix(prefix)
        return @apis.values.select{ |doc_info| doc_info[:path].index(prefix) == 0 }
      end
      def self.get_infos_for_token_prefix(prefix)
        return @apis.values.select{ |doc_info| doc_info[:name].index(prefix) == 0 }
      end
      def self.extract_return_types(doc_info)
        return doc_info[:return] && doc_info[:return].first || []
      end
    end # module DocProviderStub

  end

end

class ClassA
  CONSTANT ||= 42
  def self.class_method_a; end
  def instance_method_a; end
  XX = 81
  class XY; end
  module XZ; end
  def self.xx; end
  def self.xy; end
  def self.xz; end
  def yx; end
  def yy; end
  def yz; end
  module ModuleB
    def self.module_function_b; end
  end
  module ModuleB1 # same methods as ModuleB
    def self.module_function_b; end
  end
  module ModuleB2 # not same methods as ModuleB
  end
  class ClassB
    def self.class_method_b; end
    def instance_method_b; end
  end
end
INSTANCE_A ||= ClassA.new
class ClassA1 # same methods as ClassA
  CONSTANT ||= 42
  def self.class_method_a; end
  def instance_method_a; end
end
class ClassA2 # not same methods as ClassA
end
