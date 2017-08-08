module AE

  module ConsolePlugin

    class FeatureDocumentation

      require(File.join(PATH, 'features', 'docprovider.rb'))
      require(File.join(PATH, 'features', 'autocompleter.rb'))
      require(File.join(PATH, 'bridge.rb'))
      require(File.join(PATH, 'translate.rb'))

      ERROR_PAGE_URL ||= File.join(PATH, 'html', 'docbrowser_error_page.html')

      def initialize(app)
        @documentation_browser = nil
        app.plugin.on(:console_added, &method(:initialize_console))
      end

      def initialize_console(console)
        dialog = console.dialog
        dialog.on('open_help') { |action_context, token_list|
          # Show the documentation browser.
          show_documentation_browser(dialog).then{
            # Open the help page.
            binding = console.instance_variable_get(:@binding)
            lookup(token_list, binding)
          }
          # TODO: maybe action_context.reject on failure and show a JS notification
        }
      end

      def show_documentation_browser(dialog)
        # Compute dimensions to display the documentation browser next to the console dialog.
        return dialog.get('WindowGeometry.getGeometry').then{ |x, y, w, h, screen_w, screen_h|
          width = [w, 500].min
          left = x + w # right of console dialog
          left = x - w if left > screen_w || screen_w - left < x # left of console dialog
          # Show the documentation browser.
          if @documentation_browser.nil?
            @documentation_browser = UI::HtmlDialog.new()
            Bridge.decorate(@documentation_browser)
            @documentation_browser.on('translate'){ |action_context|
              TRANSLATE.webdialog(@documentation_browser)
            }
          end
          if !@documentation_browser.visible?
            @documentation_browser.set_position(left, y)
            @documentation_browser.set_size(width, h)
          end
          @documentation_browser.show
          @documentation_browser.bring_to_front
        }
      end

      # Looks up a url for a given list of tokens and opens the url.
      # @param [Array<String>] token_list
      # @param [Binding] binding
      def lookup(tokens, binding)
        classification = Autocompleter.resolve_tokens(tokens, binding) # raises AutocompleterError
        url = DocProvider.get_documentation_url(classification)
        if !defined?(Sketchup::Http)
          @documentation_browser.set_url(url)
        else
          # Test whether url exists (Sketchup 2017+)
          Sketchup::Http::Request.new(url, Sketchup::Http::HEAD).start{ |request, response|
            if response.status_code == 200
              @documentation_browser.set_url(url)
            else
              @documentation_browser.set_file(ERROR_PAGE_URL) # TODO: or base url of documentation
              warn("Documentation not found for '#{classification.docpath}' at url #{url}") # TODO: use notification instead
            end
          }
        end
      rescue Autocompleter::AutocompleterError => error
        # Load an error page
        @documentation_browser.set_url(ERROR_PAGE_URL)
        warn("Documentation could not be resolved for '#{tokens.join}'") # TODO: use notification instead
      end

      def get_javascript_string
<<JAVASCRIPT
requirejs(['app', 'bridge', 'translate', 'window_geometry', 'get_current_tokens', 'bootstrap-notify'], function (app, Bridge, Translate, WindowGeometry, getCurrentTokens, _) {

    // Publish window_geometry to allow Bridge to call it. TODO: not very elegant.
    window.WindowGeometry = WindowGeometry;

    var commandConsoleHelp = function () {
        var tokens = getCurrentTokens(app.console.aceEditor);
        Bridge.call('open_help', tokens);
    };
    var commandEditorHelp = function () {
        if (app.settings.get('editMode') == 'ace/mode/ruby_sketchup') {
            var tokens = getCurrentTokens(app.editor.aceEditor);
            Bridge.call('open_help', tokens);
        } else {
            $.notify(Translate.get('The help function can only lookup Ruby documentation.' + ' \\n' +
                    Translate.get('If this is Ruby code, set the edit mode in the menu.')), {
                type: 'warning',
                element: $('#editorContentWrapper'),
                placement: { from: 'top', align: 'center' },
                offset: { x: 0, y: 0 },
                allow_dismiss: true
            });
        }
    };

    /**
     * Register shortcuts.
     */
    app.console.aceEditor.commands.addCommand({
        name: Translate.get('Show documentation for the currently focussed word in a browser window.'),
        bindKey: 'Ctrl-Q',
        exec: commandConsoleHelp
    });
    app.editor.aceEditor.commands.addCommand({
        name: Translate.get('Show documentation for the currently focussed word in a browser window.'),
        bindKey: 'Ctrl-Q',
        exec: commandEditorHelp
    });

    /**
     * Register events on toolbar buttons.
     * Note: Toolbar button is specified in HTML, there is no API yet to do it in this script.
     */
    $('#buttonConsoleHelp').attr('title', Translate.get('Show documentation for the currently focussed word in a browser window.')+' (Ctrl+Q)');
    $('#buttonConsoleHelp').on('click', commandConsoleHelp);

    $('#buttonEditorHelp').attr('title', Translate.get('Show documentation for the currently focussed word in a browser window.')+' (Ctrl+Q)');
    $('#buttonEditorHelp').on('click', commandEditorHelp);
});
JAVASCRIPT
      end

    end # class FeatureDocumentation

  end # module ConsolePlugin

end # module AE
