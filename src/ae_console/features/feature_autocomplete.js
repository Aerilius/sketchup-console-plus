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
  font-size: 11px;                               \
  margin: 0 0 3px 0;                             \
}                                                \
.ace_doc-tooltip p {                             \
  font-size: 9px;                                \
  margin: 2px 0 2px 0;                           \
}                                                \
.ace_doc-tooltip ul {                            \
  list-style: square;                            \
}                                                \
.ace_doc-tooltip li {                            \
  font-size: 9px;                                \
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
                    // We provide a custom insertMatch function to override the Ace built-in one.
                    // We notify the API usage counter and then call the original Ace insertMatch implementation.
                    completions[i].completer = {
                      insertMatch: function (editor, data) {
                        if (data.docpath) {
                          Bridge.call('autocompletion_inserted', data.docpath);
                        }
                        delete data.completer;
                        editor.completer.insertMatch(data);
                      }
                    };
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

    var filepathCompleter = {
        getCompletions: function (editor, session, pos, prefix, callback) {
            var fullPrefix;
            var TokenIterator = ace.require('ace/token_iterator').TokenIterator;
            var tokenIterator = new TokenIterator(editor.getSession(), pos.row, pos.column);
            var currentToken = tokenIterator.getCurrentToken(); // An object {type: string, value: string, index: number, start: number}
            if (currentToken == null) return [];
            // If we are inside a string token, just take the complete string and remember the position of ace's prefix.
            var stringRegexp = /^'(?:[^']|\\\')+'$|^"(?:[^"]|\\\")+"$/;
            if (currentToken.value.match(stringRegexp)) {
                var columnInToken = pos.column - currentToken.start;
                fullPrefix = currentToken.value.substring(1, columnInToken); // Exclude the quote character at the beginning.
            // Otherwise if the string is incomplete (we find a quote character token before), concatenate all tokens to a string.
            } else {
                fullPrefix = currentToken.value;
                while (true) {
                    currentToken = tokenIterator.stepBackward();
                    if (currentToken == null) return [];
                    if (currentToken.value.match(/^\s*?["']/)) {
                        fullPrefix = currentToken.value.substring(RegExp.$_.length) + fullPrefix;
                        break;
                    }
                    fullPrefix = currentToken.value + fullPrefix;
                }
            }
            var prefixStart = fullPrefix.length - prefix.length;
            // Assume the string fullPrefix is a filepath and query completions.
            Bridge.get('autocomplete_filepath', fullPrefix).then(function (completions) {
                for (var i = 0; i < completions.length; i++) {
                    // Restore the completion to match the prefix only, not the looked-up string.
                    completions[i].value = completions[i].value.substring(prefixStart);
                }
                callback(null, completions);
            });
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
        consoleAceEditor.completers = [runtimeCompleter, filepathCompleter];
        editorAceEditor.completers  = [runtimeCompleter, filepathCompleter, language_tools.textCompleter, language_tools.snippetCompleter];

        var Autocomplete = ace.require('ace/autocomplete').Autocomplete;
        // Patch: Ace autocomplete installs shortcuts that conflict with some used by the console and editor.
        // Return is used by the console to submit and execute the code, and by the editor to insert a line break.
        Autocomplete.prototype.commands['Return'] = null;
        // Shift-enter is used by the console to insert line breaks.
        Autocomplete.prototype.commands['Shift-Return'] = null;
    });
});
