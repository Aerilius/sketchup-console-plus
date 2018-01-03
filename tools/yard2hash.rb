#!/usr/bin/env ruby
=begin
Utility to read the yard registry and dump it to easy to read formats.

It walks recursively over yard's object graph and writes important data into a hash data structure.
This can be output as ruby hash, as json or as ruby marshalled data, either to stdout or to a file.

Usage:
    Yard2Hash.new('path/to/project').to_file('path/to/output_file', ['Module1',...], {:format=>:json})
or
    Yard2Hash.new('path/to/.yardoc').to_file('path/to/output_file', ['Module1',...], {:format=>:json})
or on command line:
    ruby yard2hash.rb --input path/to/project --node_path Sketchup,Geom,UI --format json --output path/to/output_file.json


@class   Yard2Hash
@version 1.0.0
@date    2015-08-13
@author  Andreas Eisenbarth
@license MIT License (MIT)
=end

require 'optparse'
require 'json'

begin
  require 'yard'
rescue LoadError
  error = nil
  [
    '/usr/lib/ruby/vendor_ruby/yard.rb',
    'Z:/usr/lib/ruby/vendor_ruby/yard.rb',
    'Z:/home/andreas/.rvm/gems/ruby-2.0.0-p353/gems/yard-0.9.9/lib/yard.rb'
  ].each{ |path|
    begin
      load(path)
      error = nil
      break
    rescue LoadError, Errno::ENOENT => e
      error = e
      next
    end
  }
  raise error unless error.nil?
end

begin
  require 'awesome_print' # Optional, for debugging using pretty-print.
rescue LoadError
end

class Yard2Hash

  # Create a new Yard2Hash instance and load the yard registry.
  # @param [String] path  The path to a ruby project's source directory.
  def initialize(path)
    YARD::Registry.clear
    if path[/\.yardoc[^\/\\]*$/]
      YARD::Registry.load(path)
    elsif File.exist?(File.join(path, '.yardoc'))
      path = File.join(path, '.yardoc')
      YARD::Registry.load(path)
    else
      YARD.parse(path)
    end
  end

  # Return a hash of all data that is interesting for us.
  # @param [Array<String>] node_paths     One or more strings in Ruby's class path convention specifying the
  #                                       modules or classes to output.
  # @param [Hash<Symbol,Object>] options  An options hash, see {#tree_to_hash}.
  # @return [Hash]  A hash with class paths as keys and hashes containing properties of an item.
  # @example Form of the returned hash
  #     "Class::Path#method" => {
  #       :namespace => "Class::Path",
  #       :name => "method",
  #       :path => "Class::Path#method",
  #       :type => :method,
  #       :description => "The descriptive text",
  #       :visibility  => :public,
  #       :parameters => [["name", ["Object", ...], "description"], ...],
  #       :return =>      [         "Object",       "description"]
  #     }
  def to_hash(node_paths, options={})
    registry_hash = {}
    if node_paths.empty?
      YARD::Registry.root.children.select{ |node|
        node.type == :module || node.type == :class
      }.each{ |node|
        tree_to_hash(node, registry_hash, options)
      }
    else
      node_paths.each { |node_path|
        tree_to_hash(YARD::Registry.at(node_path), registry_hash, options)
      }
    end
    return registry_hash
  end

  # Return a json string of all data that is interesting for us.
  # @param [Array<String>] node_paths       One or more strings in Ruby's class path convention specifying the
  #                                         modules or classes to output.
  # @param [Hash<Symbol,Object>] options    An options hash, see {#tree_to_hash}.
  # @option options [Boolean] :pretty_print Whether to print human-readable json.
  # @return [String]                        A json string with class paths as keys, see {#to_hash}.
  def to_json(node_paths, options={})
    registry_hash = to_hash(node_paths, options)
    json_options = {}
    if options[:pretty_print]
      json_options = {
          :indent    => "\t",
          :space     => ' ',
          :object_nl => "\n",
          :array_nl  => "\n"
      }
    end
    return JSON.generate(registry_hash, json_options)
  end

  # Return a ruby marshal dump of all data that is interesting for us.
  # @param [Array<String>] node_paths     One or more strings in Ruby's class path convention specifying the
  #                                       modules or classes to output.
  # @param [Hash<Symbol,Object>] options  An options hash, see {#tree_to_hash}
  # @return [String]                      A marshal dump with class paths as keys, see {#to_hash}
  def to_marshal(node_paths, options)
    registry_hash = to_hash(node_paths, options)
    # TODO: The following command cannot be unmarshalled without class YARD. It must have saved references to YARD.
    # return Marshal.dump(registry_hash)
    return Marshal.dump(eval(registry_hash.inspect))
  end

  # Write yard registry data to a file, in the specified format.
  # @param [String] output_file           The file to write the data to. Overwrites if the file exists.
  # @param [Array<String>] node_paths     One or more strings in Ruby's class path convention specifying the
  #                                       modules or classes to output.
  # @param [Hash<Symbol,Object>] options  An options hash, see {#tree_to_hash}.
  # @option options [Symbol] :format      The desired file format, either :json, :hash or :marshal
  def to_file(output_file, node_paths, options)
    if File.extname(output_file).empty?
      output_file += case options[:format]
        when :json then '.json'
        when :hash then '.rb'
        when :marshal then '.dump'
      end
    end
    File.open(output_file, 'wb') { |file|
      to_io(file, node_paths, options)
    }
  end

  # Write yard registry data to standard output, in the specified format.
  # @param [Array<String>] node_paths     One or more strings in Ruby's class path convention specifying the
  #                                       modules or classes to output.
  # @param [Hash<Symbol,Object>] options  An options hash, see {#to_file}, {#tree_to_hash}.
  def to_stdout(node_paths, options)
    to_io($stdout, node_paths, options)
  end

  private

  # Write yard registry data to an IO object, in the specified format.
  # @param [IO] io                        An IO object like a file or standard output.
  # @param [Array<String>] node_paths     One or more strings in Ruby's class path convention specifying the
  #                                       modules or classes to output.
  # @param [Hash<Symbol,Object>] options  An options hash, see {#to_file}, {#tree_to_hash}
  def to_io(io, node_paths, options)
    case options[:format]
    when :json
      io.puts to_json(node_paths, options)
    when :hash
      if options[:pretty_print] && defined?(awesome_inspect)
        io.puts to_hash(node_paths, options).awesome_inspect({:plain=>true, :index=>false})
      else
        io.puts to_hash(node_paths, options).inspect
      end
    when :marshal
      io.puts to_marshal(node_paths, options)
    end
  end

  # Walk over the yard registry tree and collect node data to a hash.
  # @param [Object]              node     A YARD::CodeObject::Base subclass
  # @param [Hash]                target   A hash into which to insert the result
  # @param [Hash<Symbol,Object>] options  An options hash, currently supporting
  # @option options [Fixnum]    :levels   The maximum amount of recursion levels
  # @param [Fixnum]              level    The current recursion level (for internal use).
  def tree_to_hash(node, target, options={}, level=1)
    levels = options[:levels] || 5

    # Node data of YARD::CodeObjects::Base
    node_hash = {
        :description => node.docstring,
        :name        => node.name,
        :namespace   => node.namespace && node.namespace.path,
        :path        => node.path,
        :type        => node.type # :module, :class, :constant, :method...
    }
    # Differentiate the method type.
    if node_hash[:type] == :method
      node_hash[:type] = (node.namespace.type == :module) ? :module_function :
                         (node.scope == :class) ? :class_method : :instance_method
    end

    # Add type info to constants
    if node.type == :constant
      node_hash[:return] = [resolve_module_path(node.path).class.to_s, ''] rescue nil
    end
    
    # Optional node data of subclasses of YARD::CodeObjects::Base
    node_hash[:visibility] = node.visibility if node.respond_to?(:visibility)
    if node.type == :method
      if node.has_tag?(:param)
        node_hash[:parameters] = node.tags(:param).map { |tag|
          [tag.name, tag.types, tag.text] # TODO: Also use default value?
        }
      end
      if node.has_tag?(:return)
        tag = node.tag(:return)
        node_hash[:return] = [tag.types, tag.text]
      end
    end

    # Store the node data in the target hash.
    target[node.path] = node_hash

    # If there are aliases, store copies of the node data for each in the target hash.
    if node.type == :method && node.respond_to?(:aliases)
      node.aliases.each { |_alias|
        # For MethodObject, :aliases gives [Array<MethodObject>] ClassObject
        # For ClassObject, :aliases would be [Array<Array(MethodObject,Symbol)>]
        alias_object = _alias
        node_hash[:path] = alias_object.path
        node_hash[:name] = alias_object.name
        target[alias_object.path] = node_hash
      }
    end

    # If there are child nodes, walk recursively over the tree.
    if node.respond_to?(:children) && level < levels
      children = node.children.sort_by { |child| child.to_s }
      children.each { |child|
        tree_to_hash(child, target, options, level+1)
      }
    end
  end

  def resolve_module_path(module_path)
    tokens = module_path.split(/\:\:|\.|\#/)
    namespace = Kernel
    until tokens.empty?
      namespace = namespace.const_get(tokens.shift)
      raise NameError('Nested constant not found') if namespace.nil?
    end
    return namespace
  end

  class << self

    private

    # Main function when run from command line.
    def main
      input_directory = nil
      output_file = nil
      nodes = []
      options = {
          :format => :json,
          :pretty_print => false,
          :levels => 5
      }
      OptionParser.new { |opts|
        opts.banner = 'Usage: yard2hash.rb [options]'
        opts.on('-i', '--input FILE', 'Input ruby project\'s source directory or a .yardoc directory.') { |dir|
          input_directory = dir
        }.on('-n', '--node_path x,y,z', Array, 'The nodes to output') { |_nodes|
          nodes = _nodes
        }.on('-o', '--output FILE', String, 'Output directory') { |file|
          output_file = file
        }.on('-f', '--format FORMAT', String, [:json, :hash, :marshal],
             'Format of the output, either json, hash, marshal') { |format|
          options[:format] = format.to_sym
        }.on('-p', '--pretty_print', 'Pretty-print the output with indentation') {
          options[:pretty_print] = true
        }.on('-l', '--levels NUMBER', Numeric, 'Maximum recursion levels') { |levels|
          options[:levels] = levels
        }
      }.parse!

      unless input_directory && File.directory?(input_directory)
        puts 'An existing source directory must be given as --input parameter.'
        exit 1
      end

      if output_file
        if File.exist?(File.dirname(output_file))
          Yard2Hash.new(input_directory)
          .to_file(output_file, nodes, options)
        else
          puts 'The directory for the given output file does not exist. Nothing exported.'
          exit 1
        end
      else
        Yard2Hash.new(input_directory)
        .to_stdout(nodes, options)
      end
    end

  end # class << self

  # If loaded in Sketchup, we don't want to execute it at load.
  # If run from command line, execute it.
  unless defined?(Sketchup)
    main()
  end

end # class Yard2Hash
