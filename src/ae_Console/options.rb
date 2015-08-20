=begin

Permission to use, copy, modify, and distribute this software for
any purpose and without fee is hereby granted, provided that the above
copyright notice appear in all copies.

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

Name:         options.rb
Author:       Andreas Eisenbarth
Description:  Class to store and retrieve options/settings.
              It works like a Hash but is type-safe. That means an option can 
              only be updated to the same type. Unexpected nil values or corrupted
              data from the registry are ignored and won't cause type errors.
              Options can only be of a JSON compatible class (no subclasses currently). 
              It is intended for configurations with limited character range only 
              (no user data with special characters).
Usage:        Create an instance:        @options = Options.new("MyPlugin", default={key => value})
              Get an option:             @options.get(String||Symbol)
                                         @options[String||Symbol]
              Get an option and provide default (if not yet set in initialization):
                                         @options.get(String||Symbol, default)
                                         @options[String||Symbol]=(value)
              Set an option:             @options.set(String||Symbol, value)
              Get all options:           @options.get_all
              Update all options:        @options.update(new_options={key => value})
              Save all options to disk:  @options.save
              Reset to original state:   @options.reset
              Migrate from old format:   @options.migrate(minimum_old_version, new_version){ |old_key, old_value| [new_key, new_value] }
Version:      1.2.0
Date:         08.05.2014

=end


module AE


class Console


class Options


@@dict = "Plugins_ae"
@@valid_types = [String, Symbol, Fixnum, Float, Array, Hash, TrueClass, FalseClass, NilClass]


# Create a new instance and fill it with saved options or a provided defaults.
# @param [Module, String] namespace  The name space for looking up from the registry or configuration files.
# @param [Hash]           default    The default options
def initialize(namespace, default={})
  raise(ArgumentError, "Argument 'namespace' must be a String or Module to identify the option.") unless namespace.is_a?(String) || namespace.is_a?(Module)
  raise(ArgumentError, "Optional argument 'default' must be a Hash.") unless default.nil? || default.is_a?(Hash)
  @namespace = (namespace.is_a?(Module)) ? namespace.name[/[^\:]+$/] : namespace
  @version = (defined?(namespace::VERSION)) ? namespace::VERSION : "0.0.0"
  filter_types(default)
  @default = Marshal.dump(default) # Allows later to create deep copies.
  @options = default
  self.update(read())
end


# Get a value for a key.
# @param  [Symbol] key
# @param  [Object] default  A default value if key is not found
# @return [Object] value    A value with a type of @@valid_types
def get(key, default=nil)
  raise(ArgumentError, "Argument 'key' must be a String or Symbol.") unless key.is_a?(String) || key.is_a?(Symbol)
  key = key.to_sym unless key.is_a?(Symbol)
  return (@options.include?(key)) ? @options[key] : default
end
alias_method(:[], :get)


# Set a value for a key.
# @param [Symbol] key
# @param [Object] value  A value with a type of @@valid_types
def set(key, value)
  raise(ArgumentError, "Argument 'key' must be a String or Symbol.") unless key.is_a?(String) || key.is_a?(Symbol)
  raise(ArgumentError, "Not a valid type for Options.[]=") unless @@valid_types.include?(value.class)
  self.update({key => value})
end
alias_method(:[]=, :set)


# Returns all options as a Hash.
def get_all
  return @options.clone
end


# Updates all options with new ones with same type.
# @param [Hash] hash  A hash of new data to be merged
def update(hash)
  raise(ArgumentError, "Argument 'hash' must be a Hash.") unless hash.is_a?(Hash)
  # Remove invalid types.
  hash = filter_types(hash)
  # Remove new keys that are not yet included.
  # hash.reject!{ |key, value| !@options.include?(key) }
  # Merge only if the new value has the same type as the old value.
  @options.merge!(hash){ |key, old_value, new_value|
    new_value = new_value.to_sym if old_value.class == Symbol && new_value.class == String
    new_value = new_value.to_f if old_value.class == Float && new_value.class == Fixnum
    if
      # Accept updated values only if they have the same type as the old value.
      (new_value.class == old_value.class ||
      # Do a special test for Boolean which consists in Ruby of two classes (TrueClass != FalseClass).
        old_value == true && new_value == false || old_value == false && new_value == true) &&
      # If value is an array, check the class of array elements.
      (old_value.class == Array && (old_value.empty? || new_value.empty? || !new_value.find{ |v| v.class != old_value.first.class }) || true)
    then
      new_value
    else
      old_value
    end
  }
  return self
end


# Saves the options to disk.
def save
  @options[:version] = @version
  if Sketchup.version.to_i >= 14
    Sketchup.write_default(@@dict, @namespace, @options)
  else
    string = Sketchup.write_default(@@dict, @namespace, @options.inspect.inspect[1...-1])
    #string = Sketchup.write_default(@@dict, @namespace, @options.inspect.gsub(/\"/, "'"))
  end
  return self
end


# Resets the options to the plugin's original state.
# This is useful to get rid of corrupted options and prevent saving and reloading them to the registry.
def reset
  @options = Marshal.load(@default)
  return self
end


# Allows to migrate options from an older version of the plugin.
# @overload migrate(new_version)
#   @param  [String] new_version      Version from which on a new format was used.
# @overload migrate(min_version, new_version)
#   @param  [String] min_version      Optional minimum required version that the block is able to migrate.
#   @param  [String] new_version      Version from which on a new format was used.
# @yield    A code block that is run for every option stored in this object.
# @yieldparam  [Symbol] key           The key of the option.
# @yieldparam  [Object] value         The key of the option (of a JSON-compatible type).
# @yieldreturn [Array(Object,Object)] The new key and the new value for the option.
def migrate(*args, &block)
  min_version = (args.length > 1) ? args.first : "0.0.0"
  new_version = (args.length == 1) ? args.first : args[1]
  # Migrate if the version in the registry is smaller than the version with which a new format was introduced.
  return self unless compare_version(@options[:version] || "0", new_version) < 0
  # Don not migrate if the version in the registry is at smaller than the minimum 
  # version for which the migration function has been defined.
  return self unless compare_version(@options[:version] || min_version, min_version) >= 0
  hash = {}
  read().each{ |key, value|
    new_key, new_value = block.call(key, value)
    hash[new_key] = new_value unless new_key.nil?
  }
  @options.merge!(hash)
  @options[:version] = @version
  save
  return self
end


# Reads the options from disk.
def read
  if Sketchup.version.to_i >= 14
    default = Sketchup.read_default(@@dict, @namespace, {})
  else
  string = Sketchup.read_default(@@dict, @namespace, "{}")
  default = eval(string) if string.is_a?(String)
  end
  return (default.is_a?(Hash)) ? default : {}
rescue Exception => e
  if defined?(AE::Console)
    AE::Console.error(e)
  else
    $stderr.write(e.message << $/)
    $stderr.write(e.backtrace.join($/) << $/)
  end
  return {}
end
private :read


# Remove all keys whose value is not allowed. Set all keys to Symbols.
# Remove all keys that are neither Symbol nor String.
# @param [Hash] hash
def filter_types(hash)
  hash.clone.each{ |k, v|
    hash.delete(k) unless @@valid_types.include?(v.class)
    if k.is_a?(String)
      hash.delete(k)
      hash[k.gsub(/\-/, "_").to_sym] = v
    elsif !k.is_a?(Symbol) # elsunless
      hash.delete(k)
    end
  }
  return hash
end
private :filter_types


# Compare two version strings
# @param  [String]  string1
# @param  [String]  string2
# @return [TrueClass,FalseClass]
def compare_version(string1, string2)
  version1 = string1.split(".").map{ |s| s.to_i }
  version2 = string2.split(".").map{ |s| s.to_i }
  result = 0
  result = version1.shift.to_i <=> version2.shift.to_i until result != 0 || version1.empty? && version2.empty?
  return result
end
private :compare_version


end # @class Options


end


end # @module AE
