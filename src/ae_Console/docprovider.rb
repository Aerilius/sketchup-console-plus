=begin
This module gives access to Ruby documentation generated through yard doc.

@module  DocProvider
@version 1.0.0
@date    2015-08-13
@author  Andreas Eisenbarth
@license MIT License (MIT)

=end
module AE


  class Console


    module DocProvider


      @apis = {}


      @directory = nil


      # Set the directory where API dumps are stored and try to load them.
      # @param [String] doc_directory  The directory where Marshal dumps generated with Yard2Hash are stored.
      # TODO: don't distribute marshalled data, depends on versions
      def self.set_directory(doc_directory)
        return if doc_directory == @directory
        # Iterate over all files in the directory that match the .dump extension.
        Dir.entries(doc_directory).each{ |file|
          next if file == '.' || file == '..' || !file[/\.dump$/]
          # Open the file. Apparently `File.read` stops after some bytes on Windows, it needs binary mode.
          path = File.join(doc_directory, file)
          File.open(path, "rb"){ |f|
            string = f.read
            begin
              result = Marshal.load(string)
            rescue TypeError, ArgumentError, EncodingError
              $stderr.write("#{self} failed loading #{path}\n")
              next
            end
            # When successfully unmarshalled, add it to the APIs.
            @apis.merge!(result) if result.is_a?(Hash)
          }
        }
        @directory = doc_directory
      end


      # Get documentation for a symbol given by its object path in Ruby notation, and the type of the
      # @param [String] path A symbol path in Ruby notation, like:
      #                      Sketchup.active_model
      #                      Sketchup::Edge#length
      #                      Geom::IDENTITY
      # #@param [String] type A symbol of the type, like:
      #     :global_variable, :constant, :class_variable, :instance_variable, :class_method, :instance_method
      def self.get_documentation_html(path)
        return nil unless @apis.include?(path)
        item = @apis[path]
        return nil unless item[:description] && !item[:description].empty?
        html = nil
        #case item[:type]
        #when :method
          parameters = item[:parameters]
          returned = item[:return]
          signature = "<strong>#{item[:name]}</strong>"
          parameters_section = ''
          return_section = ''
          if parameters && !parameters.empty?
            signature += '(' + parameters.map { |param|
              "#{param[0]}"
            }.join(', ') + ')'
            parameters_section += "<p><b>#{TRANSLATE['Parameters']}:</b></p><ul>"
            parameters.each{ |param|
              parameters_section += "<li><b>#{param[0]}</b> (<tt>#{param[1]}</tt>) — #{param[2]}</li>"
            }
            parameters_section += '</ul>'
          end
          if returned
            signature += ' → ' + "<tt>#{returned[0]}</tt>"
            return_section += "<p><b>#{TRANSLATE['Return value']}:</b></p><ul>"
            return_section += "[#{returned[0]}] – #{returned[1]}"
            return_section += '</ul'
          end
          html = "<h3>#{signature}</h3><hl/><p>#{item[:description]}</p>#{parameters_section}#{return_section}"
        #end
        return html
      end


      # Load a new .yardoc registry into the DocProvider and cache it in the apis folder.
      def self.load(registry_directory, node_paths)
        require(File.join(DIR, 'yard2hash.rb'))
        yard2hash = Yard2Hash.new(registry_directory)
        file_name = node_paths.first.gsub(/::/, '_').downcase
        output_file = unique_filepath(@directory, file_name)
        options = {:format => :marshal}
        yard2hash.to_file(output_file, node_paths, options)
        @apis.merge(yard2hash.to_hash(node_paths, options))
      end


      def self.generate(registry_directory, node_paths)
        # TODO: generate yard doc here first
        self.load(registry_directory, node_paths)
      end


      # For a given class path, get the class paths of the possible types of the return value.
      # @param  [String] path    A ruby class path specifying a (nested) module/class or method
      # @return [Array<String>]  An array of the class paths. If a method was given, the class paths of return values
      #                          are returned. If a variable/constant was given, the class path of its type is returned.
      # @example
      #   get_type_paths('String#length') # => ['Fixnum']
      # TODO: support type of constant etc.
      def self.get_type_paths(path)
        return [] unless @apis.include?(path)
        item = @apis[path]
        returned = item[:return]
        return [] unless returned
        type_string = returned[0]
        return [] unless type_string
        # Strip out wrapped [], strip out nested type exressions like `Array<String>`
        main_types = type_string.gsub(/^\[|\]$/, '').gsub(/<[^>]*>|\([^\)]*\)/, '')
        return main_types.split(/,/).map{ |type|
          type.split(/\b/)
        }.compact
      end


      class << self


        private


        # Create a valid, unique file path from a random string.
        # @param  [String] dir     The directory where the file should go.
        # @param  [String] string  The desired filename.
        # @return [String]         The cleaned-up unique file path.
        def unique_filepath(dir, string)
          # Clean up basename.
          string = string[/.{1,30}/].gsub(/\n|\r/, '').gsub(/[^0-9a-zA-Z\-\_\.\(\)\#]+/, '_').gsub(/^_+|_+$/, '').to_s
          string = 'file' if string.empty?
          base = File.join(dir, string)
          # Detect collision of filenames and return alternative filename (numbered).
          base_orig = base
          i = 0
          while Dir.entries(@directory).find{ |dir| dir.index(base) == 0 }
            base = base_orig + i.to_s
            i += 1
          end
          return base
        end


      end


    end


  end


end