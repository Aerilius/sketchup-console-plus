# Load the normal support files.
require 'sketchup.rb'
require 'extensions.rb'

# Create the extension.
ext = SketchupExtension.new('Ruby Console+', File.join('ae_Console', 'main.rb'))

# Attach some nice info.
ext.creator     = 'Aerilius'
ext.version     = '2.2.0'
ext.copyright   = '2012-2015 Andreas Eisenbarth'
ext.description = 'An alternative Ruby Console with command history and code highlighting.'

# Register and load the extension on startup.
Sketchup.register_extension(ext, true)
