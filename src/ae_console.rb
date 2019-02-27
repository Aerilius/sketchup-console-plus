# Load the normal support files.
require 'sketchup.rb'
require 'extensions.rb'

module AE

  module ConsolePlugin

    self::PATH = File.join(File.expand_path('..', __FILE__), 'ae_console') unless defined?(self::PATH)

    require File.join(PATH, 'version.rb')
    require File.join(PATH, 'translate.rb')

    self::TRANSLATE = Translate.new('console.strings') unless defined?(self::TRANSLATE)

    # Create the extension.
    ext = SketchupExtension.new(self::TRANSLATE['Ruby Console+'], File.join(PATH, 'core.rb'))

    # Attach some nice info.
    ext.creator     = 'Aerilius'
    ext.version     = AE::ConsolePlugin::VERSION
    ext.copyright   = '2012-2019 Andreas Eisenbarth'
    ext.description = self::TRANSLATE['An alternative Ruby Console with many useful features.']

    # Register and load the extension on startup.
    Sketchup.register_extension(ext, true)

  end

end
