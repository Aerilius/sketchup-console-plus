// TODO: Pour tous les deux, console et editor, change focus to input after each button click.

var AE = window.AE || {};

AE.Console = AE.Console || {};

AE.Console.Console = function(aceEditor, output, settings) {

    var console = this,
        console_id = 'js:',// TODO: remove
        message_id = 0,    // TODO: remove
        lineNumber = 1;

    function initialize () {
        configureAce(aceEditor);
        //output.setLineNumber(lineNumber); // TODO: implement line number handling: global line numbering
        // or per executed code snippet
    }

    // Implementation of Observer/Observable

    this.addListener = function (eventName, fn) {
        $(console).on(eventName, function (event, args) {
            fn.apply(undefined, args);
        });
    };

    function trigger (eventName, data) {
        var args = Array.prototype.slice.call(arguments).slice(1);
        $(console).trigger(eventName, [args]); // TODO: instead of console was this. Evt. correct all trigger functions
    }

    function configureAce(aceEditor) {
        // This autoresizes the editor.
        aceEditor.setOption('maxLines', 1000);
        // Inject a custom gutter renderer to set our own line numbers.
        // Or on every update of output: aceEditor.session.$firstLineNumber = lineNumber
        aceEditor.session.gutterRenderer  = {
            getWidth: function(session, lastLineNumber, config) {
                return lastLineNumber.toString().length *
                    config.characterWidth
            },
            getText: function(session, row) {
                return lineNumber + row;
            }
        };

        // Keyhandler to submit code for evaluation if Enter is pressed.
        aceEditor.commands.addCommand({
            name: 'Evaluate code',
            bindKey: 'enter',
            exec: function (editor) {
                // Get the input.
                var command = console.getContent();
                // Submit it.
                console.submit(command);
                // Clear the input field.
                console.clearInput();
                consoleInput.scrollIntoView();
                // TODO: Cancel propagation?
            },
            readOnly: true // false if this command should not apply in readOnly mode
        });

        // Keyhandler to override up/down navigation.
        aceEditor.commands.addCommand({
            name: AE.Translate.get('Go one line up or back in the history.'),
            bindKey: 'up',
            exec: function (editor) {
                // If the cursor is in the first row.
                if (editor.getCursorPosition().row === 0) {
                    trigger('arrowUp', editor);
                } else {
                    editor.navigateUp();
                }
            }
        });

        // Keyhandler to override up/down navigation.
        aceEditor.commands.addCommand({
            name: AE.Translate.get('Go one line down or forward in the history.'),
            bindKey: 'down',
            exec: function (editor) {
                // If the cursor is in the last row.
                if (editor.getCursorPosition().row + 1 === editor.session.getLength()) {
                    trigger('arrowDown', editor);
                } else {
                    editor.navigateDown();
                }
            }
        });
    }

    this.focus = function () {
        aceEditor.focus();
    };

    this.setContent = function (content) {
        aceEditor.session.setValue(content);
    };

    this.getContent = function () {
        return aceEditor.session.getValue();
    };

    this.getCurrentTokens = function () {
        return []; // TODO
    };

    this.clearOutput = function () {
        output.clear();
        aceEditor.focus();
    };

    this.clearInput = function () {
        aceEditor.session.setValue('');
    };

    this.submit = function (text) {
        // Increase the message count.
        message_id++;
        // Add the command to the output.
        var metadata = {
            type: 'input',
            language: settings.get('language')
            /*, id: console_id + message_id*/  // TODO: remove message ids
        };
        //trigger('input', text, metadata); // TODO: check extensions that want to modify text.
        //output.add(text, metadata);
        //AE.Console.input(text, metadata);
        trigger('input', text, metadata);
        if (output) output.add(text, metadata);
        // No need to eval empty commands.
        if (!text || /^\s*$/.test(text)) return;
        // Evaluate the command.
        if (settings.get('language') === 'javascript') {
            // Language is JavaScript and we eval it here.
            try {
                var result = JSON.stringify(globalEval(text));
                metadata = {
                    type: 'result',
                    language: 'javascript',
                    time: (new Date),
                    source: metadata.id
                };
                AE.Console.result(result, metadata);
                //trigger('result', result, metadata);
                //output.add(result, metadata);
            } catch (e) {
                /* This is already caught by `window.onerror` with complete metadata while here `e` has for some reason no properties. */
                //AE.Console.error(e, {type: "result", language: "javascript", time: (new Date), source: metadata.id });
            }
        } else {
            // Language is Ruby.
            var newMetadata = $.extend({}, metadata, {
                id:     message_id++,
                source: metadata.id
            });
            Bridge.get('eval', text, lineNumber, metadata).then(function (result, metadata) {
                $.extend(newMetadata, metadata, {type: 'result'});
                trigger('result', result, newMetadata);
                output.add(result, newMetadata); // TODO: or let output only listen to events on console?
            }, function (metadata) {
                $.extend(newMetadata, metadata, {type: 'error'});
                var errorMessage = metadata.message;
                trigger('error', errorMessage, metadata);
                output.add(errorMessage, metadata);
            });
            lineNumber += text.split(/\r\n|\r|\n/).length;
        }
    };

    /**
     * Add code-highlighting to a string.
     * @note This function leverages ace's highlight capabilities outside of the editor.
     *   Here we turn invisible editing characters off so that they won't pollute the
     *   produced html if someone wants to select & copy text.
     *   The used language is the mode currently set in the ace.editor.session.
     * @param {string} string
     * @returns {string} - A string of html code with css classes for code-highlighting.
     */
    output.highlight = function (string) {
        if (typeof string !== 'string' || string === '') {
            return '';
        }
        var orig_showInvisibles = aceEditor.renderer.getShowInvisibles();
        aceEditor.renderer.setShowInvisibles(false);
        var html = [];
        var strings = string.split(/\r?\n/);
        for (var i = 0; i < strings.length; i++) {
            if (strings[i] === '') {
                html.push('<br/>');
                continue;
            }
            var data = aceEditor.session.getMode().getTokenizer().getLineTokens(strings[i], 'start');
            aceEditor.renderer.$textLayer.$renderSimpleLine(html, data.tokens);
            if (i + 1 < strings.length) {
                html.push('<br/>');
            }
        }
        aceEditor.renderer.setShowInvisibles(orig_showInvisibles);
        return html.join('');
    };

    initialize();
};

/**
 * Evalutes JavaScript code in a global context and returns the return value.
 * @method
 * @note obtained from: http://whattheheadsaid.com/2011/08/global-eval-with-a-result-in-internet-explorer
 */
var globalEval = (function () {
    var isIndirectEvalGlobal = (function (original) {
        try {
            // Does `Object` resolve to a local variable, or to a global, built-in `Object`,
            // reference to which we passed as a first argument?
            return window.eval('Object') === original;
        }
        catch (error) {
            // if indirect eval errors out (as allowed per ES3), then just bail out with `false`
            return false;
        }
    })(Object);

    if (isIndirectEvalGlobal) {
        // if indirect eval executes code globally, use it
        return function (expression) {
            return window.eval(expression)
        };
    } else if ('execScript' in window) {
        // if `window.execScript` exists, use it along with `eval` to obtain a result
        return function (expression) {
            globalEval.___inputExpression___ = '(' + expression + ')';
            window.execScript('globalEval.___lastInputResult___ = eval(globalEval.___inputExpression___)');
            return globalEval.___lastInputResult___;
        };
    } else {
        return function (expression) {
            AE.Console.javaScriptError(new Error('no globalEval defined'));
            return expression;
        }
    }
})();
