module AE

  module ConsolePlugin

    class FeatureDocumentation

      require(File.join(PATH, 'features', 'docprovider.rb'))
      require(File.join(PATH, 'features', 'tokenresolver.rb'))
      require(File.join(PATH, 'bridge.rb'))
      require(File.join(PATH, 'translate.rb'))

      ERROR_PAGE_HTML ||= File.join(PATH, 'html', 'documentation_error_page.html')

      def initialize(app)
        @documentation_browser = nil
        @error_message = nil
        @settings = app.settings
        app.plugin.on(:console_added, &method(:initialize_console))
      end

      def initialize_console(console)
        dialog = console.dialog
        dialog.on('open_help') { |action_context, tokens|
          # Show the documentation browser.
          show_documentation_browser(dialog).then{
            # Open the help page.
            binding = console.instance_variable_get(:@binding)
            lookup(tokens, binding)
          }
        }
      end

      def show_documentation_browser(dialog)
        # Compute dimensions to display the documentation browser next to the console dialog.
        return dialog.get('WindowGeometry.getGeometry').then{ |x, y, w, h, screen_w, screen_h|
          min_width = 500
          if dialog.is_a?(UI::HtmlDialog)
            x, y, w, h, screen_w, screen_h, min_width = [x, y, w, h, screen_w, screen_h, min_width].map{ |n|
              n * UI.scale_factor
            }
          end
          width = [w, min_width].min
          # Place the documentation browser at the same vertical position either left or right of the console.
          # Placing the documentation browser right, its left coordinate is:
          left = x + w # right of console dialog
          # Placing it left if it would be outside of the screen or if there is more available space on the left.
          left = x - width if left > screen_w || screen_w - left < x # left of console dialog
          # Initialize the documentation browser and return a promise that is resolved once the html is loaded.
          if @documentation_browser.nil?
            initialize_documentation_browser
          end
          # Otherwise just show the documentation browser.
          if !@documentation_browser.visible?
            @documentation_browser.set_position(left, y)
            @documentation_browser.set_size(width, h)
            @documentation_browser.show
          else
            @documentation_browser.bring_to_front
          end
          next true
        }
      end

      def initialize_documentation_browser
        properties = {
            :dialog_title    => TRANSLATE['Documentation'],
            :scrollable      => false,
            :resizable       => true,
        }
        if defined?(UI::HtmlDialog)
          properties[:style] = UI::HtmlDialog::STYLE_DIALOG
          @documentation_browser = UI::HtmlDialog.new(properties)
        else
          @documentation_browser = UI::WebDialog.new(properties)
        end

        # Add a Bridge to handle JavaScript-Ruby communication.
        @documentation_browser = Bridge.decorate(@documentation_browser)

        @documentation_browser.on('translate') { |action_context|
          TRANSLATE.webdialog(@documentation_browser)
        }

        @documentation_browser.on('get_settings') { |action_context| 
          action_context.resolve @settings.to_hash
        }

        @documentation_browser.on('update_property') { |action_context, key, value|
          @settings[key] = value
        }

        @documentation_browser.on('get_error_message') { |action_context|
          action_context.resolve @error_message unless @error_message.nil?
        }
      end

      # Looks up a url for a given list of tokens and opens the url.
      # @param [Array<String>] tokens
      # @param [Binding] binding
      def lookup(tokens, binding)
        classification = TokenResolver.resolve_tokens(tokens, binding) # raises ResolverError
        url = DocProvider.get_documentation_url(classification)
        if !defined?(Sketchup::Http)
          @documentation_browser.set_url(url)
        else
          # Test whether url exists (Sketchup 2017+)
          Sketchup::Http::Request.new(url, Sketchup::Http::HEAD).start{ |request, response|
            if response.status_code == 200
              @documentation_browser.set_url(url)
            else
              @error_message = TRANSLATE["Documentation for %0 not found at url %1", classification.docpath, url]
              @documentation_browser.set_url(ERROR_PAGE_HTML)
            end
          }
        end
      rescue TokenResolver::TokenResolverError => error
        # Load an error page
        @error_message = error.message
        @documentation_browser.set_url(ERROR_PAGE_HTML)
      end

      def get_javascript_string
<<-'JAVASCRIPT'
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
            $.notify(Translate.get('The help function can only lookup Ruby documentation.' + ' \n' +
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
