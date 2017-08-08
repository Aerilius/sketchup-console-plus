requirejs(['app', 'bridge', 'translate', 'ace/ace', 'get_current_tokens'], function (app, Bridge, Translate, ace, getCurrentTokens) {

    ace.require('ace/lib/dom').importCssString(" \
/* Adjust size of autocompleter */               \
.ace_editor.ace_autocomplete {                   \
  width: 160px !important; /* default: 280px */  \
}                                                \
.ace_tooltip.ace_doc-tooltip {                   \
  white-space: normal; /* allow line wrapping */ \
  color: #4d5259; /* ruby.sketchup.com */        \
}                                                \
/* Adjust size of autocompleter doc tooltip */   \
.ace_doc-tooltip h3 {                            \
  font-size: 10px;                               \
  margin: 0 0 3px 0;                             \
}                                                \
.ace_doc-tooltip p {                             \
  font-size: 8px;                                \
  margin: 2px 0 2px 0;                           \
}                                                \
.ace_doc-tooltip ul {                            \
  list-style: square;                            \
}                                                \
.ace_doc-tooltip li {                            \
  font-size: 8px;                                \
  margin-left: 3em;                              \
  text-indent: -3em;                             \
  list-style: square;                            \
}                                                \
.ace_doc-tooltip tt {                            \
  font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', \
       'Consolas', 'source-code-pro', monospace; \
}                                                ");

    // We define a new runtimeCompleter that queries completions from Ruby's introspection methods.
    var textCompleter;
    var runtimeCompleter = {
        getCompletions: function (editor, session, pos, prefix, callback) {
            // Use this autocompleter only when mode is ruby.
            if (editor.session.$modeId != 'ace/mode/ruby_sketchup' && editor.session.$modeId != 'ace/mode/ruby') return [];
            // The prefix provided by ace uses a poor splitting regexp instead of the tokenizer.
            //   Example: leading @@ and @ are missing from the prefix.
            // Instead, we take the prefix from the current token from the tokenizer.
            // To get the completion correctly inserted, we must give to ace a 
            // completion relative to the original prefix, that means subtract 
            // any surplus in front of the prefix.
            var tokens = getCurrentTokens(editor);
            var currentToken = tokens.pop(); // Prefix refers to this token.
            if (currentToken == null) return [];
            var prefixStart = currentToken.search(prefix);
            var prefixEnd = prefixStart + prefix.length;
            prefix = currentToken.substring(0, prefixEnd);
            // Query SketchUp for completions.
            // if (tokens.length == 0) textCompleter.getCompletions(editor, session, pos, prefix, callback);
            Bridge.get('autocomplete_tokens', tokens, prefix).then(function (completions) {
                for (var i = 0; i < completions.length; i++) {
                    // Restore the completion to match the prefix only, not the looked-up string.
                    completions[i].value = completions[i].value.substring(prefixStart);
                }
                callback(null, completions);
            });
        },
        // Ace queries documentation for a token.
        getDocTooltip: function (autocompletionItem) {
            return {
                docHTML: autocompletionItem.docHTML
            };
        }
    };

    ace.config.loadModule('ace/ext/language_tools', function (language_tools) {
        var consoleAceEditor = app.console.aceEditor;
        var editorAceEditor  = app.editor.aceEditor;

        // Enable autocompletion
        consoleAceEditor.setOptions({
            enableBasicAutocompletion: true,
            enableLiveAutocompletion: true,
            enableSnippets: true
        });
        editorAceEditor.setOptions({
            enableBasicAutocompletion: true,
            enableLiveAutocompletion: true,
            enableSnippets: true
        });

        // Add the runtimeCompleter and remove default completers (except snippetCompleter).
        // The keyWordCompleter includes by default Ruby on Rails method names that are not available in SketchUp.
        // The textCompleter has too many irrelevant results, even worse due to the fuzzy filter.
        consoleAceEditor.completers = [runtimeComplete];
        editorAceEditor.completers  = [runtimeComplete, language_tools.textCompleter, language_tools.snippetCompleter];

        var Autocomplete = ace.require('ace/autocomplete').Autocomplete;
        // Patch: Ace autocomplete installs shortcuts that conflict with some used by the console and editor.
        // Return is used by the console to submit and execute the code, and by the editor to insert a line break.
        Autocomplete.prototype.commands['Return'] = null;
        // Shift-enter is used by the console to insert line breaks.
        Autocomplete.prototype.commands['Shift-Return'] = null;
    });
});
