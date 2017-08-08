require 'json.rb'

module AE

  module ConsolePlugin

    # This module gives access to Ruby documentation generated through yard doc.
    module DocProvider

      # The directory where Marshal dumps generated with Yard2Hash are stored.
      API_PATH = File.join(PATH, 'apis') unless defined?(self::API_PATH)

      # [Hash<String,Hash>] docpath => doc_info
      @apis ||= {}

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
        toplevel_namespace = classification.namespace.to_s[/^[^\:]+/]
        if ['Sketchup', 'UI', 'Geom', 'LanguageHandler', 'Length', 'SketchupExtension'].include?(toplevel_namespace)
          return get_documentation_url_sketchup(classification)
        else # if Ruby core
          return get_documentation_url_ruby_core(classification)
        # else if Ruby stdlib
        # TODO: How to detect and handle standard library? "http://ruby-doc.org/stdlib-#{RUBY_VERSION}/libdoc/#{library_name}/rdoc/"
        end
      end

      # Generates an HTML string of documentation for the given docpath
      # @param classification [AE::ConsolePlugin::TokenClassification] Describes an object/method in Ruby
      # @return [String] an HTML string
      def self.get_documentation_html(classification)
        doc_info = get_info_for_docpath(classification.docpath)
        doc_info = get_info_for_docpath(classification.namespace+'#initialize') if doc_info.nil? && classification.token == 'new'
        doc_info = get_info_for_docpath(classification.namespace+'.new')        if doc_info.nil? && classification.token == 'initialize'
        raise DocNotFoundError.new("Documentation not found for #{classification}") if doc_info.nil?
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
        description = escape(doc_info[:description])
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
        return @apis.keys.select{ |key| key.to_s.index(docpath) == 0 }.map{ |key| @apis[key] }
      end

      class << self

        private

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

        def get_documentation_url_ruby_core(classification)
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

        HTML_ENCODING_MAP ||= {
          '&' => '&amp;',
          '<' => '&lt;',
          '>' => '&gt;',
          '"' => '&quot;',
          "'" => '&#39;',
          '/' => '&#x2F;',
          '`' => '&#x60;',
          '=' => '&#x3D;'
        }

        def escape(text)
          return text.gsub(/[&<>"'`=\/]/){ |match|
             HTML_ENCODING_MAP[match]
          }
        end

      end # class << self

      class DocNotFoundError < StandardError; end

      DocProvider.load_apis(Dir.glob(File.join(API_PATH, '*.json')))

    end

  end

end
