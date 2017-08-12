define(['jquery', './bridge', './translate'], function ($, Bridge, Translate) {
    return function (aceEditor, output, settings) {

        var console = this,
            message_id = 0
            lineNumber = 1;
        this.aceEditor = aceEditor;

        function initialize () {
            configureAce(aceEditor);
        }

        // Implementation of Observer/Observable

        this.addListener = function (eventName, fn) {
            $(console).on(eventName, function (event, args) {
                fn.apply(undefined, args);
            });
        };

        function trigger (eventName, data) {
            var args = Array.prototype.slice.call(arguments).slice(1);
            $(console).trigger(eventName, [args]);
        }

        function configureAce (aceEditor) {
            // Set the mode to Ruby.
            aceEditor.session.setMode('ace/mode/ruby_sketchup');
            // This autoresizes the editor.
            aceEditor.setOption('maxLines', 1000);
            // Inject a custom gutter renderer to set our own line numbers.
            // Or on every update of output: aceEditor.session.$firstLineNumber = lineNumber
            aceEditor.session.gutterRenderer = {
                getWidth: function(session, lastLineNumber, config) {
                    return lastLineNumber.toString().length * config.characterWidth;
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
                },
                readOnly: true // false if this command should not apply in readOnly mode
            });
            // Keyhandler to clear the output
            aceEditor.commands.addCommand({
                name: 'Clear the output',
                bindKey: 'ctrl-l',
                exec: function (editor) {
                    // Clear the output.
                    output.clear();
                },
                readOnly: true
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

        this.clearOutput = function () {
            output.clear();
            aceEditor.focus();
        };

        this.clearInput = function () {
            aceEditor.session.setValue('');
        };

        this.submit = function (text) {
            // Add the command to the output.
            var inputMetadata = {
                type: 'input',
                line_number: lineNumber,
                id:     message_id++,
            };
            trigger('input', text, inputMetadata);
            output.add(text, inputMetadata);
            // Evaluate the command.
            var promise = Bridge.get('eval', text, lineNumber, inputMetadata);
            trigger('eval', text, inputMetadata, promise);
            promise.then(function (result, resultMetadata) {
                resultMetadata = $.extend({}, resultMetadata, {type: 'result', source: inputMetadata.id});
                trigger('result', result, resultMetadata);
                output.add(result, resultMetadata);
            }, function (errorMetadata) {
                errorMetadata = $.extend({}, errorMetadata, {type: 'error', source: inputMetadata.id});
                var errorMessage = errorMetadata.message;
                trigger('error', errorMessage, errorMetadata);
                output.add(errorMessage, errorMetadata);
            });
            lineNumber += text.split(/\r\n|\r|\n/).length;
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
});
