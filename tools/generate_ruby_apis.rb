#!/usr/bin/env ruby
# This script runs yardoc on the Ruby source installed by rvm 
# and generates a yardoc database extract for use with ae_console.
# See here for more info on how yardoc is able to parse ruby source:
#   http://gnuu.org/2009/12/15/using-yri-for-ruby-core-classes/
#
# Requirements:
# - ruby source to be installed in ~/.rvm
# - yardoc installed (`gem install yard`)
#
# Usage:
# - cd into the tools directory
# - `ruby generate_ruby_apis.rb` 2.2.4

def generate_yardoc(includes, yardoc_db)
  system("yardoc --db #{yardoc_db} --no-output --no-api --no-private #{includes.join(' ')}")
end

def generate_apis(yardoc_db, api_output)
  system("ruby ./yard2hash.rb --input #{yardoc_db} --format json --output #{api_output}")
end

def main(ruby_version)
  # Parameters
  api_dir         = "../src/ae_console/apis"
  source_dir      = "~/.rvm/src/ruby-#{ruby_version}"
  # Since the Ruby source directly contains source files in the directory root besides many unrelated folders, we include only .c and .h files.
  core_includes   = %w'*.c'  # *.h
  # We only include interesting stdlib and extension files.
  stdlib_includes = %w'base64 benchmark cmath csv debug delegate fileutils find forwardable getoptlong ipaddr logger mathn matrix observer open3 open-uri optionparser optparse ostruct pp prettyprint rubygems scanf set singleton tmpdir unicode_normalize uri yaml'
  ext_includes    = %w'date digest fiber fiddle io json mathn openssl pathname readline ripper socket stringio win32 win32ole zlib'
  #stdlib_excludes = %w'rdoc'
  #ext_excludes    = %w'tk' # Not useful for SketchUp and too big.
  
  # Ruby core
  yardoc_db = "./.yardoc_ruby-core-#{ruby_version}"
  includes = core_includes.map{ |name| File.join(source_dir, name) }
  api_output = File.join(api_dir, "ruby-core-#{ruby_version}.json")
  generate_yardoc(includes, yardoc_db)
  generate_apis(yardoc_db, api_output)
  
  # Ruby Standard lib
  yardoc_db = "./.yardoc_ruby-stdlib-#{ruby_version}"
  includes = stdlib_includes.map{ |name| File.join(source_dir, 'lib', name) }
        .map{ |path| [path+'.rb', path] }.flatten # Take both library file and corresponding folder
        .concat(ext_includes.map{ |name| File.join(source_dir, 'ext', name) })
  api_output = File.join(api_dir, "ruby-stdlib-#{ruby_version}.json")
  generate_yardoc(includes, yardoc_db)
  generate_apis(yardoc_db, api_output)
end

if ARGV.length < 1
  raise ArgumentError.new('Ruby version number required.')
end

main(*ARGV)
