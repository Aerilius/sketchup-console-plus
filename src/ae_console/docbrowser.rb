=begin
This class allows to open documentation websites for a given Ruby token (token list).

@class   DocBrowser
@version 1.0.0
@date    2015-08-15
@author  Andreas Eisenbarth
@license MIT License (MIT)

=end
module AE


  class Console
    require(File.join(DIR, 'autocompleter.rb'))


    class DocBrowser < UI::WebDialog


      SKETCHUP_DOC_URL = 'http://www.rubydoc.info/github/jimfoltz/SketchUp-Ruby-API-Doc/master/' unless defined?(self::SKETCHUP_DOC_URL)

      ERROR_PAGE_URL = File.join(DIR, 'html', 'docbrowser_error_page.html') unless defined?(self::ERROR_PAGE_URL)

      @@instance = nil


      # Opens the documentation browser window.
      # @param [Numeric] x  The window's x coordinate
      # @param [Numeric] y  The window's y coordinate
      # @param [Numeric] w  The window's width
      # @param [Numeric] h  The window's height
      def self.open(x=nil, y=nil, w=nil, h=nil)
        if @@instance.nil?
          @@instance = self.new()
          @@instance.set_position(x.to_i, y.to_i) if x.is_a?(Numeric) && y.is_a?(Numeric)
          @@instance.set_size(w.to_i, h.to_i) if w.is_a?(Numeric) && h.is_a?(Numeric)
          @@instance.show
        elsif !@@instance.visible?
          @@instance.set_position(x.to_i, y.to_i) if x.is_a?(Numeric) && y.is_a?(Numeric)
          @@instance.set_size(w.to_i, h.to_i) if w.is_a?(Numeric) && h.is_a?(Numeric)
          @@instance.show
        end
        return @@instance
      end


      # Looks up a url for a given list of tokens and opens the url.
      # @param [Array<String>] token_list
      # @param [Binding] binding
      def lookup(token_list, binding_object, binding)
        url = build_url(token_list, binding_object, binding)
        set_url(url)
      rescue Autocompleter::AutocompleterException => error
        Console.puts('following error in open_help') # TODO
        Console.error(error)
        # Load an error page
        set_url(ERROR_PAGE_URL)
      end


      private


      # Generates a url for a given list of tokens.
      # @param [Array<String>] token_list
      # @param [Binding] binding
      # @return [String] url
      # @raise [Autocompleter::AutocompleterException]
      def build_url(token_list, binding_object, binding)
        # Get the path of the token to look up.
        path, type = Autocompleter.classify_token(token_list, binding_object, binding)

        # Then build a url from it.
        # rubydoc.info uses urls of the following form:
        #   …/NameSpace/Module/Class#methodname-instance_method
        modules = path.split(/::|#|\./)
        anchor = ''
        case type
        when :class, :module
          # Go to the page of the class/module. So we kee the modules list complete and don't need an anchor.
        when :constant, :instance_method, :class_method
          anchor = modules.pop + "-#{type}"
        else
          raise("Unknown how to build url for `#{type}`")
        end

        # Build the url.
        if ['Sketchup', 'UI', 'Geom'].include?(modules.first)
          url = SKETCHUP_DOC_URL + modules.join('/')
          url += '#' + anchor unless anchor.empty?
        else
          # This may lead to a load error if the composed url does not exist on that site.
          # Because of that we allow only toplevel modules that we know.
          #raise("`#{modules.first}` is likely not available")
          # Fallback: TODO: or choose different documentation site.
          url = SKETCHUP_DOC_URL + 'top-level-namespace'
        end

        puts [path, type].inspect+"\n"+url # TODO: debug
        return url
      end


    end


  end


end