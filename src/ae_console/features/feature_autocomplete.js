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
            var tokens = getCurrentTokens(editor);
            // Ace splits tokens sometimes incorrectly. 
            // We can pass the corrected prefix to
            // Ruby, but ace would replace the incomplete prefix by the 
            // corrected one and lead to duplication.
            // We later subtract the correction from the completions.
            var toBeSubtracted = null;
            var last = tokens[tokens.length-1];
            var missingPrefixes = ['@@', '@', ''];
            for (var i = 0; i < missingPrefixes.length; i++) {
                var prefix2 = missingPrefixes[i];
                if (last == prefix2 + prefix) {
                    prefix = prefix2 + prefix;
                    toBeSubtracted = prefix2;
                    tokens.pop();
                    break;
                }
            }
            // Query SketchUp for completions.
            // if (tokens.length == 0) textCompleter.getCompletions(editor, session, pos, prefix, callback);
            Bridge.get('autocomplete_token_list', tokens, prefix).then(function (completions) {
                for (var i = 0; i < completions.length; i++) {
                    if (toBeSubtracted) completions[i].value = completions[i].value.substring(toBeSubtracted.length);
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
        language_tools.setCompleters([runtimeCompleter, language_tools.snippetCompleter]);

        var Autocomplete = ace.require('ace/autocomplete').Autocomplete;
        // Patch: Ace autocomplete installs shortcuts that conflict with some used by the console and editor.
        // Return is used by the console to submit and execute the code, and by the editor to insert a line break.
        Autocomplete.prototype.commands['Return'] = null;
        /*Autocomplete.prototype.commands.Return = function (editor) {
            // Actually we should patch only the instance of Autocomplete that is used by the console, 
            // but we don't have access to it, so we switch depending on whether the console is focused.
            if (consoleAceEditor.isFocused()) {
                // If live autocompletion is on and the first autoselected completion is selected, we cancel and
                // let the console handle enter to submit and execute the code.
                if (editor.getOption('enableLiveAutocompletion') && editor.completer.popup.getRow() == 0) {
                    editor.completer.detach();
                    // Allow bubbling of the Return key event, so the default action (Console submit) is triggered.
                    return false;
                } else {
                    // If a lower completion has been selected (intentionally), we allow enter to accept it.
                    editor.completer.insertMatch();
                }
            } else if (editorAceEditor.isFocused()) {
                // Default enter action.
                editor.completer.insertMatch();
            }
        };*/
        // Shift-enter is used by the console to insert line breaks.
        Autocomplete.prototype.commands['Shift-Return'] = null;
    });
});
