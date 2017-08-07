#!/usr/bin/env ruby
# This script runs yardoc on the SketchUp API doc source
# and generates a yardoc database extract for use with ae_console.
#
# Requirements:
# - SketchUp API doc source to be installed and the path below adapted
# - yardoc installed (`gem install yard`)
#
# Usage:
# - cd into the tools directory
# - `ruby generate_sketchup_apis.rb`

def generate_yardoc(includes, yardoc_db)
  system("yardoc --db #{yardoc_db} --no-output --no-api --no-private #{includes.join(' ')}")
end

def generate_apis(yardoc_db, api_output)
  system("ruby ./yard2hash.rb --input #{yardoc_db} --format json --output #{api_output}")
end

def main(*argv)
  # Parameters
  api_dir         = "../src/ae_console/apis"
  source_dir      = "~/Programmierung/Repos/ruby-api-stubs/SketchUp"
  
  # SketchUp
  yardoc_db = "./.yardoc_sketchup"
  includes = [source_dir]
  api_output = File.join(api_dir, "sketchup.json")
  generate_yardoc(includes, yardoc_db)
  generate_apis(yardoc_db, api_output)
end

main(*ARGV)
