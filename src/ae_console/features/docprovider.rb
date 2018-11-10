require 'json.rb'

module AE

  module ConsolePlugin

    # This module gives access to Ruby documentation generated through yard doc.
    module DocProvider

      # The directory where Marshal dumps generated with Yard2Hash are stored.
      API_PATH = File.join(PATH, 'apis') unless defined?(self::API_PATH)

      # [Hash<String,Hash>] docpath => doc_info
      @apis ||= {}
      # Direct lookup by a token
      # token => Array<doc_infos>
      @hash_by_token ||= {}
      # Ordered for binary any range searches
      # Array<doc_infos>
      @index_by_token = []
      # Ordered for binary any range searches
      # Array<doc_infos>
      @index_by_docpath = []

      # Loads API docs found in path
      # @param filepaths [String] one or more files to load.
      def self.load_apis(*filepaths)
        filepaths.flatten.each{ |filepath|
          File.open(filepath, 'r'){ |f|
            string = f.read
            begin
              api = JSON.parse(string, :symbolize_names => true)
              @apis.merge!(api) if api.is_a?(Hash)
            rescue JSON::JSONError
              $stderr.write("#{self} failed to load #{filepath}\n")
              next
            end
          }
        }
        # Initialize search indices.
        initialize_hash_by_token(@apis)
        initialize_index_by_docpath()
        initialize_index_by_token()
        nil
      end

      # Generates a URL where documentation for the given docpath can be found
      # @param classification [AE::ConsolePlugin::TokenClassification] Describes an object/method in Ruby
      # @return [String] a URL
      def self.get_documentation_url(classification)
        toplevel_namespace = classification.namespace.to_s[/^[^\:]+/] || classification.token
        sketchup_keywords = ['Sketchup', 'UI', 'Geom', 'LanguageHandler', 'Length', 'SketchupExtension']
        if sketchup_keywords.include?(toplevel_namespace)
          return get_documentation_url_sketchup(classification)
        else # if Ruby core and stdlib
          return get_documentation_url_rubydoc_info(classification)
        end
      end

      # Generates an HTML string of documentation for the given docpath
      # @param classification [AE::ConsolePlugin::TokenClassification] Describes an object/method in Ruby
      # @return [String] an HTML string
      def self.get_documentation_html(classification)
        doc_info = get_info_for_docpath(classification.docpath)
        doc_info = get_info_for_docpath(classification.namespace+'#initialize') if doc_info.nil? && classification.token == 'new'
        doc_info = get_info_for_docpath(classification.namespace+'.new')        if doc_info.nil? && classification.token == 'initialize'
        raise(DocNotFoundError, "Documentation not found for #{classification.inspect}") if doc_info.nil?
        # Generate HTML
        return nil unless doc_info[:description] && !doc_info[:description].empty?
        html = nil
        parameters = doc_info[:parameters]
        returned = doc_info[:return]
        signature = "<strong>#{escape(doc_info[:name])}</strong>"
        parameters_section = ''
        return_section = ''
        if parameters && !parameters.empty?
          signature += '(' + escape(parameters.map(&:first).map(&:to_s).join(', ')) + ')'
          parameters_section += "<p><b>#{TRANSLATE['Parameters']}:</b></p><ul>"
          parameters.each{ |param|
            param_name, param_types, param_description = *param
            param_type_expression = (param_types.is_a?(Array)) ? param_types.map{ |s| escape(s) }.join(', ') : '?'
            parameters_section += "<li><b>#{escape(param_name)}</b> (<tt>#{param_type_expression}</tt>) — #{escape(param_description)}</li>"
          }
          parameters_section += '</ul>'
        end
        if returned
          return_types, return_description = *returned
          return_type_expression = (return_types.is_a?(Array)) ? return_types.map{ |s| escape(s) }.join(', ') : '?'
          signature += ' ⇒ ' + "<tt>#{escape(return_type_expression)}</tt>"
          if doc_info[:type].to_s != 'constant'
            return_section += "<p><b>#{TRANSLATE['Return value']}:</b></p><ul>"
            return_section += "<li>(<tt>#{return_type_expression}</tt>)"
            return_section += " — #{escape(return_description)}</li>" if return_description && !return_description.empty?
            return_section += '</ul>'
          end
        end
        description = escape(rdoc_to_html(doc_info[:description]))
        html = "<h3>#{signature}</h3><hl></hl><p>#{description}</p>#{parameters_section}#{return_section}"
        return html
      end

      # Returns the API info for a given doc path or nil.
      # @param docpath [String] A string identifying a module/class/constant or method.
      # @return [Hash, nil]
      def self.get_info_for_docpath(docpath)
        return @apis[docpath.to_sym]
      end

      # Given a doc path this method returns all API infos that match the beginning of the doc path.
      # For example if a class path is given, all methods and constants below that path are returned.
      # @param docpath [String] A prefix of a doc path
      # @return [Array<Hash>]
      def self.get_infos_for_docpath_prefix(docpath)
        return BinarySearch.search_by_prefix(@index_by_docpath, docpath){ |doc_info| doc_info[:path] }
      end

      # Returns API infos for a given token for all classes that provide this token.
      # @param token [String] A token
      # @return [Array<Hash>]
      def self.get_infos_for_token(token)
        return @hash_by_token[token] || []
      end

      # Given a prefix of a token this method returns all API infos for matching tokens.
      # @param token [String] A token
      # @return [Array<Hash>]
      def self.get_infos_for_token_prefix(prefix)
        return BinarySearch.search_by_prefix(@index_by_token, prefix){ |doc_info| doc_info[:name] }
      end

      # @param doc_info [Hash] A string of type declarations as parsed by yardoc.
      # @return [Array<String>]
      # @private
      def self.extract_return_types(doc_info)
        # doc_info[:return] is a tuple of an array of string of comma separated 
        # class names (in Yard type syntax) and a description string.
        return [] unless doc_info[:return] && doc_info[:return].first
        return_types = doc_info[:return].first # Array
        return parse_return_types(return_types, doc_info[:namespace])
      end

      def self.parse_return_types(return_types, self_type='NilClass')
        return [] unless return_types.is_a?(String) || return_types.is_a?(Array)
        return return_types.map{ |s| parse_return_types(s, self_type) }.flatten if return_types.is_a?(Array)
        # Parse the yardoc type string
        # Remove nested types
        return_types.gsub!(/^\[|\]$/, '')
        return_types.gsub!(/<[^>]*>|\([^\)]*\)/, '')
        # Split into array of type names.
        return return_types.split(/,\s*/).compact.map{ |type|
          # Resolve type naming conventions to class names.
          case type
          when 'nil' then 'NilClass'
          when 'true' then 'TrueClass'
          when 'false' then 'FalseClass'
          when 'Boolean' then 'TrueClass' # TrueClass and FalseClass have same methods.
          when '0' then 'Fixnum'
          when 'self' then self_type
          when 'void' then 'NilClass'
          else type
          end
        }
      end

      class << self

        private

        def initialize_hash_by_token(api)
          api.each{ |docpath, doc_info|
            token = doc_info[:name]
            @hash_by_token[token] ||= []
            # This inserts a reference to the same hash, data is not duplicated.
            @hash_by_token[token] << doc_info
          }
        end

        def initialize_index_by_token()
          @index_by_token = @apis.values.sort_by{ |doc_info| doc_info[:name] }
        end

        def initialize_index_by_docpath()
          @index_by_docpath = @apis.values.sort_by{ |doc_info| doc_info[:path] }
        end

        def get_documentation_url_sketchup(classification)
          host = 'http://ruby.sketchup.com/'
          # Compose URL resource path from namespace.
          if classification.type == :class || classification.type == :module
            path = classification.namespace.to_s.split('::').push(classification.token).join('/') + '.html'
          else
            path = classification.namespace.to_s.split('::').join('/') + '.html'
          end
          # Lookup type of item (class/module, constant, instance method, class method)
          fragment = case classification.type
          when :instance_method
            "##{classification.token}-instance_method"
          when :class_method, :module_function
            "##{classification.token}-class_method"
          when :constant
            "##{classification.token}-constant"
          else
            ''
          end
          # Compose URL fragment from type if item.
          return host + path + fragment
        end

        def get_documentation_url_rubydoc_info(classification)
          host = 'http://www.rubydoc.info/stdlib/core/'
          # Compose URL resource path from namespace.
          if classification.type == :class || classification.type == :module
            path = classification.namespace.to_s.split('::').push(classification.token).join('/') + '.html'
          else
            path = classification.namespace.to_s.split('::').join('/') + '.html'
          end
          # Lookup type of item (class/module, constant, instance method, class method)
          fragment = case classification.type
          when :instance_method
            "##{classification.token}-instance_method"
          when :class_method, :module_function
            "##{classification.token}-class_method"
          when :constant
            "##{classification.token}-constant"
          else
            ''
          end
          # Compose URL fragment from type if item.
          return host + path + fragment
        end

        def get_documentation_url_ruby_doc_org(classification)
          host = "http://ruby-doc.org/core-#{RUBY_VERSION}/"
          # Compose URL resource path from namespace.
          if classification.type == :class || classification.type == :module
            path = classification.namespace.to_s.split('::').push(classification.token).join('/') + '.html'
          else
            # TODO: handle empty namespace (top-level methods)
            path = classification.namespace.to_s.split('::').join('/') + '.html'
          end
          # Lookup type of item (class/module, constant, instance method, class method)
          encoded_token = classification.token.to_s.split(/(\W+)/).map{ |chars|
            if chars[/^\W+$/]
              chars.split()
              .map{ |char| char.ord.to_s(16).upcase } # hexadecimal encoding
              .join('-')
            else
              chars
            end
          }.join('-')
          
          fragment = case classification.type
          when :instance_method
            "#method-i-#{encoded_token}"
          when :class_method, :module_function
            "#method-c-#{encoded_token}"
          when :constant
            "##{encoded_token}"
          else
            ''
          end
          # Compose URL fragment from type if item.
          return host + path + fragment
        end

        HTML_ENCODING_MAP = {
          '&' => '&amp;',
          '<' => '&lt;',
          '>' => '&gt;',
          '"' => '&quot;',
          "'" => '&#39;',
          '/' => '&#x2F;',
          '`' => '&#x60;',
          '=' => '&#x3D;'
        } unless defined?(HTML_ENCODING_MAP)

        def escape(text)
          return text.to_s.gsub(/&nbsp;|<\/?\w+>|<\w+\/>|[&<>"'`=\/]/){ |match|
             match.length == 1 ? HTML_ENCODING_MAP[match] : match
          }
        end


        RDOC_TO_HTML_MAP = Hash[{
          '+'  => 'tt',
          '_'  => 'i',
          '*'  => 'i',
          '__' => 'b',
          '**' => 'b'
        }.map{ |markup, tagname|
          regexp      = Regexp.new("\\b#{Regexp.quote(markup)}(\\w[\\w\\s]*\\w)#{Regexp.quote(markup)}\\b")
          replacement = "<#{tagname}>\\1</#{tagname}>"
          [regexp, replacement]
        }] unless defined?(RDOC_TO_HTML_MAP)

        def rdoc_to_html(text)
          text = text.clone
          RDOC_TO_HTML_MAP.each{ |regexp, replacement|
            # Markup
            text.gsub!(regexp, replacement)
          }
          # Spaces
          text.gsub!(/  +/){ |spaces| '&nbsp;'*spaces.length }
          # Line breaks
          text.gsub!(/\n/, '<br/>')
          return text
        end

      end # class << self

      class DocNotFoundError < StandardError; end

      module BinarySearch

        # Returns the first item that matches exactly the searched value.
        # @param array [Array]   The sorted array to search through
        # @yieldparam  [Object]  An optional attribute getter that returns the string property to compare. 
        #                        If not provided, items from the array are directly compared.
        # @yieldreturn  [String]
        # @return [Object]       The first item in the array that fulfills the comparison.
        def self.search_exact(array, value, &get_attribute)
          if block_given?
            index = binary_search_lowest_index(array){ |item| value <= get_attribute.call(item) }
            greater_or_equal = array[index]
            return (value == get_attribute.call(greater_or_equal)) ? greater_or_equal : nil
          else
            # Equal to `array.include?(value) ? value : nil`
            index = binary_search_lowest_index(array){ |item| value <= item }
            greater_or_equal = array[index]
            return (value == greater_or_equal) ? greater_or_equal : nil
          end
        end

        # @param array  [Array<Object>] The sorted array to search through
        # @param prefix [String] The string prefix for which all matches should be found
        # @yieldparam   [Object] An optional attribute getter that returns the string property to compare. 
        #                        If not provided, items from the array are directly compared.
        # @yieldreturn  [String]
        # @return [Array<Object>] An array containing the range of items that match the prefix.
        def self.search_by_prefix(array, prefix, &get_attribute)
          raise ArgumentError.new("Prefix must have at least one character") if prefix.empty?
          # Prefix is the lowest prefix for which all greater or equal items are desired.
          # The lowest prefix for which all greater or equal items are not desired
          prefix_succ = prefix[0...-1] + (prefix[-1].ord+1).chr
          if block_given?
            first_index      = binary_search_lowest_index(array){ |item| prefix      <= get_attribute.call(item) }
            after_last_index = binary_search_lowest_index(array){ |item| prefix_succ <= get_attribute.call(item) }
          else
            first_index      = binary_search_lowest_index(array){ |item| prefix      <= item }
            after_last_index = binary_search_lowest_index(array){ |item| prefix_succ <= item }
          end
          if first_index < after_last_index
            return array[first_index...after_last_index]
          else
            return []
          end
        end

        class << self

          private

          # @param array [Array]      The sorted array to search through
          # @yieldparam  [Comparable] The block is given the item to compare.
          # @yieldreturn [Boolean]    The block returns true if the searched item is less or equal the given one.
          # @return [Integer]         The lowest index that fulfills the comparison, or the length of the array
          def binary_search_lowest_index(array, &comparison)
            return binary_search_lowest_index_impl(array, 0, array.length, &comparison)
          end

          # @param array [Array]   The sorted array to search through
          # @param first [Integer] The lower index to include
          # @param last  [Integer] The upper index not to include anymore
          # @yieldparam  [Comparable]
          # @yieldreturn [Boolean]
          # @return [Integer]      The lowest index that fulfills the comparison, or the upper limit of the search.
          def binary_search_lowest_index_impl(array, first, last, &comparison)
            # Empty range, not found
            return first-1 if first == last
            # One item
            return comparison.call(array[first]) ? first : last if first == last-1
            # Multiple items, split by a pivot and recurse.
            pivot = first + ( (last - first) / 2 )
            if comparison.call(array[pivot])
              return binary_search_lowest_index_impl(array, first, pivot, &comparison)
            else
              return binary_search_lowest_index_impl(array, pivot, last,  &comparison)
            end
          end

        end

      end

      DocProvider.load_apis(Dir.glob(File.join(API_PATH, '*.json')))

    end

  end

end
