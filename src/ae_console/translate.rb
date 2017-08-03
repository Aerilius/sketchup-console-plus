=begin

based on langhandler.rb
Copyright 2005-2008, Google, Inc.

Permission to use, copy, modify, and distribute this software for
any purpose and without fee is hereby granted, provided that the above
copyright notice appear in all copies.

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

Name:         translate.rb
Author:       Andreas Eisenbarth
Description:  Class to translate single strings or webdialogs
Usage:        Have translation files of the scheme
                toolname_EN.strings with "original string"="translated string";
              or a Ruby file (.rb) with a Hash
              Create an instance:        translate = Translate.new(toolname, translation_directory)
              Translate a single string: translate[String]
              Translate a webdialog:     translate.webdialog(UI::WebDialog)
Version:      2.1
Date:         26.04.2014

=end

module AE



class Console



class Translate



  # Load translation strings.
  #
  # @param [String] toolname a name to identify the translation file (plugin name)
  # @param [String] dir an optional directory path where to search, otherwise in this file's directory
  #
  # @return [Hash-like] a class instance from which strings can be fetched like from a Hash.
  #
  def initialize(toolname=nil, dir=nil)
    @strings = {}
    @locale = Sketchup.get_locale
    parse_strings(toolname, @locale, dir)
  end


  private


  # Find translation file and parse it into a hash.
  #
  # @param [String] toolname a name to identify the translation file (plugin name)
  # @param [String] locale the locale/language to look for
  # @param [String] dir an optional directory path where to search, otherwise in this file's directory
  #
  # @return [Boolean] whether the strings have been added
  #
  def parse_strings(toolname=nil, locale="en", dir=nil)
    toolname = "" if toolname.nil?
    raise(ArgumentError, "Argument 'toolname' needs to be a String") unless toolname.is_a?(String)
    raise(ArgumentError, "Argument 'locale' needs to be a String") unless locale.is_a?(String)
    raise(ArgumentError, "Argument 'dir' needs to be a String") unless dir.is_a?(String) || dir.nil?
    dir = File.dirname(File.expand_path(__FILE__)) if dir.nil? || !File.exists?(dir.to_s)
    language = locale[/^[^\-]+/]
    extensions = ["strings", "rb"]

    available_files = Dir.entries(dir).find_all{ |f|
      File.basename(f)[/(^|#{toolname}[^a-zA-Z]?)#{locale}\.(#{extensions.join('|')})/i]
    }.concat(Dir.entries(dir).find_all{|f|
      File.basename(f)[/(^|#{toolname}[^a-zA-Z]?)#{language}(-\w{2,3})?\.(#{extensions.join('|')})/i]
    })
    return if available_files.empty?
    path = File.join(dir, available_files.first)
    format = File.extname(path)[/[^\.]+/]
    strings = {}
    File.open(path, "r"){ |file|
      # load .rb format
      if format == "rb"
        strings = eval(file.read)
      # parse .strings
      else
        entry = ""
        inComment = false
        file.each{ |line|
          if !line.include?("//")
            if line.include?("/*")
              inComment = true
            end
            if inComment==true
              if line.include?("*/")
                inComment=false
              end
            else
              entry += line
            end
          end
          if format == "strings" && entry.include?(";")
            keyvalue = entry.strip.gsub(/^\s*\"|\"\s*;$/, "").split(/\"\s*=\s*\"/)
            entry = ""
            next unless keyvalue.length == 2
            key = keyvalue[0].gsub(/\\\"/,'"').gsub(/\\\\/, "\\")
            value = keyvalue[1].gsub(/\\\"/,'"').gsub(/\\\\/, "\\")
            strings[key] = value
          end
        }
      end # if format
    }

    @strings.merge!(strings)
    return (strings.empty?)? false : true
  end


  public


  # Method to access a single translation.
  #   Args:
  #     key: original string in ruby script; % characters escaped by %%
  #     s0-sn: optional strings for substitution of %0 ... %sn
  #   Returns:
  #     string: translated string
  #
  def get(key, *si)
    raise(ArgumentError, 'Argument "key" must be a String or an Array of Strings.') unless key.is_a?(String) || key.nil? || (key.is_a?(Array) && key.grep(String).length == key.length)
    return key.map{ |k| self.[](k, *si) } if key.is_a?(Array) # Allow batch translation of strings
    puts("#{self.class} warning: key '#{key[0..20]}' not found for locale #{@locale}") unless @strings.include?(key)
    value = (@strings[key] || key).to_s.clone
    # Substitution of additional strings.
    si.compact.each_with_index{ |s, i|
      value.gsub!(/\%#{i}/, s.to_s)
    }
    value.gsub!(/\%\%/,"%")
    return value.chomp
  end
  alias_method(:[], :get)


  # Method to access all translations as hash.
  #
  # @return [Hash] key/value pairs of original and translated strings
  #
  def get_all
    return @strings
  end


  # Translate a webdialog.
  #
  # @param [UI::WebDialog] dlg a WebDialog to translate
  #   It will translate all Text nodes and title attributes.
  #   It will also offer a JavaScript function to translate single strings.
  #   Usage: ##Translate.get(string)##
  #
  def webdialog(dlg)
    script = %[
      var AE = AE || {};
      AE.Translate = function(self) {
        /* Object containing all translation strings. */
        var STRINGS = #{to_json(@strings)};
        /* Method to access a single translation. */
        self.get = function(key, s1, s2) {
          try {
            if (typeof key !== "string") { return ""; }
            // Get the string from the hash and be tolerant towards punctuation and quotes.
            var value = STRINGS[key];
            if (typeof value !== "string" || value === "") {
              value = STRINGS[ key.replace(/[\\.\\:]$/, "") ];
            }
            if (typeof value !== "string" || value === "") {
              value = STRINGS[key.replace(/\\"/g, '&quot;')];
            }
            if (typeof value !== "string" || value === "") { value = key; }
            // Substitution of additional strings.
            for (var i = 1; i < arguments.length; i++) {
              value = value.replace("%"+(i-1), arguments[i], "g");
            }
            return value;
          } catch (e) { return key || ""; }
        };
        /* Translate the complete HTML. */
        self.html = function(root) {
          if (root==null) { root = document.body; }
          var blocked = new RegExp("^(script|style)$", "i");
          var emptyString = new RegExp("^(\\n|\\s|&nbsp;)+$", "i");
          var textNodes = [];
          var nodesWithAttr = {"title": [], "placeholder": [], "alt": []};
          //# Get all text nodes that are not empty. Get also all title attributes.
          var getNodes = function(node){
            if (node && node.nodeType === 1 && !blocked.test(node.nodeName)) {
              if (node.title !== null && node.title !== "") { nodesWithAttr["title"].push(node); }
              if (node.placeholder !== null && node.placeholder !== "") { nodesWithAttr["placeholder"].push(node); }
              for (var i = 0; i < node.childNodes.length; i++) {
                var childNode = node.childNodes[i];
                if ( childNode && childNode.nodeType === 3 && !emptyString.test(childNode.nodeValue) ) {
                  textNodes.push(childNode);
                } else {
                  getNodes(childNode);
                }
              }
            }
          };
          // Translate all found text nodes.
          getNodes(root);
          for (var i = 0; i < textNodes.length; i++) {
            var text = textNodes[i].nodeValue;
            if (text.match(/^\s*$/)) { continue; }
            // Remove whitespace from the source code to make matching easier.
            var key = String(text).replace(/^(\\n|\\s|&nbsp;)+|(\\n|\\s|&nbsp;)+$/g, "");
            var value = self.get(key);
            // Return translated string with original whitespace.
            textNodes[i].nodeValue = text.replace(key, value);
          }
          for (var attr in nodesWithAttr) {
            for(var i = 0; i < nodesWithAttr[attr].length; i++) {
              try {
                var node = nodesWithAttr[attr][i];
                node.setAttribute(attr, self.get( node.getAttribute(attr) ) );
              } catch(e) {}
            }
          }
        };
        return self;
      } (AE.Translate || {});
      // Now translate the complete HTML.
      AE.Translate.html(); /* TODO: on DOMready */
    ]
    dlg.execute_script( script ) if !@strings.empty?
  end



  private



  def to_json(obj)
    return unless obj.is_a?(Hash)
    # remove non-JSON objects
    o = obj.reject{ |k, v|
      !k.is_a?(String) && !k.is_a?(Symbol) || !v.is_a?(String) && !v.is_a?(Symbol)
    }
    # Split at every even number of unescaped quotes.
    # If it's not a string then turn Symbols into String and replace => and nil.
      json_string = o.inspect.split(/(\"(?:.*?(?:[\\][\\]+?|[^\\]))*?\")/).
      map{ |s|
        (s[0..0] != '"')?                        # If we are not inside a string
        s.gsub(/\:(\S+?(?=\=>|\s))/, "\"\\1\""). # Symbols to String
          gsub(/=>/, ":").                       # Arrow to colon
          gsub(/\bnil\b/, "null") :              # nil to null
        s
      }.join()
    return json_string
  end



end # class Translate



end



end # module AE
