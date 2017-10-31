# Load the normal support files.
require 'sketchup.rb'
require 'extensions.rb'

# Create the extension.
ext = SketchupExtension.new('Ruby Console+', File.join('ae_console', 'core.rb'))

# Attach some nice info.
ext.creator     = 'Aerilius'
ext.version     = '3.0.2'
ext.copyright   = '2012-2017 Andreas Eisenbarth'
ext.description = 'An alternative Ruby Console with command history and code highlighting.'

# Register and load the extension on startup.
Sketchup.register_extension(ext, true)
