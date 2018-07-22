module AE

  module ConsolePlugin

    class Translate

      # Load translation strings.
      # @param filename [String] a name to identify the translation file.
      def initialize(filename)
        @strings = {}
        @locale  = Sketchup.get_locale
        filepath = File.join(PATH, 'Resources', @locale, filename)
        if File.exist?(filepath)
          parse_strings(filepath)
        else
          fallback_locale = 'en-US'
          filepath        = File.join(PATH, 'Resources', fallback_locale, filename)
          if File.exist?(filepath)
            @locale = fallback_locale
            parse_strings(filepath)
          else
            puts("#{self.class}: Localization for #{@locale} not found in #{filepath}")
          end
        end
      end

      # Method to access a single translation.
      # @param key           [String]        original string in ruby script; % characters escaped by %%
      # @param substitutions [Array<String>] optional strings for substitution of %0 ... %sn
      # @return              [String]        translated string
      def get(key, *substitutions)
        key = key.to_s if key.is_a?(Symbol)
        raise(ArgumentError, 'Argument "key" must be a String or an Array of Strings.') unless key.is_a?(String) || key.nil? || (key.is_a?(Array) && key.all? { |k| k.is_a?(String) })
        return key.map { |k| self.[](k, *substitutions) } if key.is_a?(Array) # Allow batch translation of strings
        if @strings.include?(key)
          value = @strings[key].clone
        else
          Kernel.warn("warning: key #{(key.length <= 20) ? key.inspect : key[0..20].inspect + '...'} not found for locale #{@locale} (#{self.class.name})\n#{caller.first}")
          value = key.to_s.clone
        end
        # Substitution of additional strings.
        substitutions.compact.each_with_index { |substitution, i|
          value.gsub!(/\%#{i}/, substitution.to_s)
        }
        value.gsub!(/%%/, '%')
        return value.chomp
      end
      alias_method(:[], :get)

      # Push translations to a webdialog and translate all html text nodes.
      # @param [UI::WebDialog] dlg a WebDialog to translate
      #   It will translate all Text nodes and title attributes.
      #   It will also offer a JavaScript function to translate single strings.
      #   Usage: ##Translate.get(string)##
      def webdialog(dlg)
        script = %[
          requirejs(['translate'], function (Translate) {
              Translate.load(#{to_json(@strings)});
              Translate.html(document.body);
          });
        ]
        dlg.execute_script(script) unless @strings.empty?
        nil
      end

      private

      # Find translation file and parse it into a hash.
      # @param filepath [String]
      # @return [Boolean] whether the strings have been added
      def parse_strings(filepath)
        strings = {}
        File.open(filepath, 'r') { |file|
          entry      = ''
          in_comment = false
          file.each { |line|
            unless line.include?('//')
              if line.include?('/*')
                in_comment = true
              end
              if in_comment
                if line.include?('*/')
                  in_comment = false
                end
              else
                entry += line
              end
            end
            if entry.include?(';')
              keyvalue = entry.strip.gsub(/^\s*"|"\s*;$/, '').split(/"\s*=\s*"/)
              entry    = ''
              next unless keyvalue.length == 2
              key          = keyvalue[0].gsub(/\\"/, '"').gsub(/\\\\/, '\\')
              value        = keyvalue[1].gsub(/\\"/, '"').gsub(/\\\\/, '\\')
              strings[key] = value
            end
          }
        }
        @strings.merge!(strings)
        return (strings.empty?) ? false : true
      end

      def to_json(obj)
        return unless obj.is_a?(Hash)
        # remove non-JSON objects
        o = obj.reject { |k, v|
          !k.is_a?(String) && !k.is_a?(Symbol) || !v.is_a?(String) && !v.is_a?(Symbol)
        }
        # Split at every even number of unescaped quotes.
        # If it's not a string then turn Symbols into String and replace => and nil.
        json_string = o.inspect.split(/(\"(?:.*?(?:[\\][\\]+?|[^\\]))*?\")/).
        map { |s|
          if s[0..0] != '"' # If we are not inside a string
            s.gsub(/:(\S+?(?==>|\s))/, '"\\1"'). # Symbols to String
              gsub(/=>/, ':'). # Arrow to colon
              gsub(/\bnil\b/, 'null') # nil to null
          else
            s
          end
        }.join()
        return json_string
      end

    end # class Translate

  end

end
