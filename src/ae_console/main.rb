=begin

Copyright 2012-2015, Andreas Eisenbarth
All Rights Reserved

Permission to use, copy, modify, and distribute this software for
any purpose and without fee is hereby granted, provided that the above
copyright notice appear in all copies.

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

Name:         console.rb
Author:       Andreas Eisenbarth
Description:  This is another Ruby Console implemented as WebDialog.
              It features a history that is saved over sessions,
              a multi-line code editor with syntax highlighting, indentation, and
              code folding. It supports opening several independent instances of
              the console.
Usage:        menu Window → Ruby Console+
              Clear: Clears the console output
              Reload: Once you have loaded a script manually ("load"), it will be
                added to this menu. All scripts in this list are automatically
                reloaded on when the files are changed.
              Execution context (text field): Insert a name of a Module, Class or
                a reference to an object to set the console's binding to that object.
                This allows you to execute private methods or access private
                instance variables.
              Select: Allows you to click an Entity in the model to get a reference
                to it in the console.
              Preferences: A menu of settings.
                - display time stamps
                - wrap lines
                - wrap into an undo operation (this has only an effect for entity
                  creation, otherwise it makes sense to turn it off)
                - select a theme for the console (colors)
                - select the font size
              Ctrl-Space|Ctrl-Shift-Space|Alt-Space: triggers the autocompletion. This plugin uses Ruby's
                reflection methods to relevant and accurate autocompletions from
                the live ObjectSpace (instead from a static file).
# TODO: check all tooltips and texts, is there something missing/untranslated? in all languages
# TODO: history: more intelligent data structure
# TODO: docprovider run yard doc
# TODO: polyfills instead of AE.Base.Events etc.
# TODO: overload *results must be handled on javascript side (?)
# TODO: Add a "long_output" or "short_output" option to message metadata to allow making expandable output → Optional
# TODO: remove or hide execution context (binding)
#       or add "load file" button? → load file or open for editing!
#       Editing mode has reload button and save button, but no select entity button.
# Current buttons: [Reload] [Clear] [Binding] [Help] [Select] [Menu]
# new Console:     [Console] [Clear]                 [Help] [Select] [Menu]
# new Editor:      [Editor]  [Open] [Run]  file.rb   [Help]  [Save]  [Menu]     Help must use type inference
# Try theming jQuery UI with native colors.
# TODO: remove multiple results in promise for resolve/reject
# TODO: Rename DIR in PATH
# TODO: Add nil to end of methods where no return value expected.
# TODO: backtraces:
begin
  #{accessor}.__send__(:#{method}, *args, &block)
rescue Exception
  $@.delete_if{|s| %r"#{Regexp.quote(__FILE__)}"o =~ s} unless Forwardable::debug
  ::Kernel::raise
end

Version:      2.1.7
Date:         15.04.2014
=end


module AE


  class Console


    unless file_loaded?(__FILE__)

      # Constants
      VERSION      = '2.1.7'
      DEBUG        = true
      self::DIR ||= File.dirname(__FILE__)
      
      # Translation
      require(File.join(DIR, "translate.rb"))
      TRANSLATE    = Translate.new('Console', File.join(DIR, 'lang'))
      
      # Load Console functionality
      require(File.join(DIR, "console.rb"))

      # Register in UI

      # Command
      command                 = UI::Command.new(TRANSLATE['Ruby Console+']) {
        AE::Console.open
      }
      if Sketchup.version.to_i >= 16
        if RUBY_PLATFORM =~ /darwin/
          command.small_icon  = command.large_icon = File.join(DIR, 'images', 'icon_console.pdf')
        else
          command.small_icon  = command.large_icon = File.join(DIR, 'images', 'icon_console.svg')
        end
      else
        command.small_icon    = File.join(DIR, 'images', 'icon_console_32.png')
        command.large_icon    = File.join(DIR, 'images', 'icon_console_48.png')
      end
      command.tooltip         = TRANSLATE['An alternative Ruby Console with multiple lines, code highlighting, entity inspection and many more features.']
      command.status_bar_text = TRANSLATE['Press the enter key to evaluate the input, and use shift-enter for linebreaks.']

      # Menu
      UI.menu('Window').add_item(command)

      # Toolbar
      toolbar = UI::Toolbar.new(TRANSLATE['Ruby Console+'])
      toolbar.add_item(command)
      # Show toolbar if it was open when we shutdown.
      toolbar.restore
      # Per bug 2902434, adding a timer call to restore the toolbar. This
      # fixes a toolbar resizing regression on PC as the restore() call
      # does not seem to work as the script is first loading.
      UI.start_timer(0.1, false) {
        toolbar.restore
      }

      file_loaded(__FILE__)
    end


  end # class Console


end # module AE
