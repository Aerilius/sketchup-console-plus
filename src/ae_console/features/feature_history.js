requirejs(['app', 'bridge', 'translate'], function (app, Bridge, Translate) {
    /**
     * History
     * Allows to navigate back to previous input.
     */
    var history;
    var tmpID = null;  // Cache the id of the last input so it can be matched to its result.
    var tmpInput = ''; // Cache the value of the last input so it can be added to the history when executed successfully.

    /**
     * @class HistoryProvider
     * This class allows to register strings and navigate back & forward.
     * This is only to provide the navigation capability on the JavaScript side.
     * A similar class on the Ruby side registers all input when it is evaled and
     * saves it to a file.
     * This history has two special features:
     * - If you repeatedly input text that is identical to one of the very previous
     *   inputs, it would become hard to navigate further back to some different inputs.
     *   Thus the history won't add a new item but just reorder the previous items.
     * - If an input causes an error, you would probably correct the error, but
     *   don't want the erronous input to be remembered (and then unintenionally repeated).
     *  Thus the history let's you correct it and forgets the erronous input soon.
     */
    var HistoryProvider = function () {
        // Same implementation in Ruby.
        var MAX_LENGTH = 100,
            selected = 0, /** negative number between zero and -(data.length) */
            currentInput = '',
            data = [];

        /**
         * Load data into the history.
         * @param array {Array<string>}
         */
        this.load = function (array) {
            if (Object.prototype.toString.call(array) !== '[object Array]') {
                return;
            }
            data = array;
        };

        this.back = function (current) {
            if (selected <= -data.length) { // Already last index in history
                return; // null
            }
            // The current input is not yet in the history, because it wasn't committed/executed.
            // But when navigating through the history and then returning, we want to be able to restore it.
            if (selected === 0 && typeof current === 'string') {
                currentInput = current;
            }
            selected -= 1;
            return data[data.length + selected];
        };

        this.forward = function () {
            if (selected >= 0) { // Already first index in history
                return; // null
            }
            selected += 1;
            if (selected === 0) {
                return currentInput;
            } else { // (selected < 0)
                return data[data.length + selected];
            }
        };

        this.push = function (value) {
            if (data.length > MAX_LENGTH) data.shift();
            selected = 0;
            data.push(value);
        };

    };

    // Keyhandler to override up/down navigation.
    app.console.aceEditor.commands.addCommand({
        name: Translate.get('Go one command back in the history.'),
        bindKey: 'up',
        exec: function (editor) {
            // If the cursor is in the first row.
            if (editor.getCursorPosition().row === 0) {
                var value = history.back(editor.getValue());
                if (typeof value === 'string') {
                    editor.setValue(value);
                    editor.navigateFileStart();
                    editor.navigateLineEnd();
                }
                editor.clearSelection();
            } else {
                editor.navigateUp();
            }
        }
    });

    // Keyhandler to override up/down navigation.
    app.console.aceEditor.commands.addCommand({
        name: Translate.get('Go one command forward in the history.'),
        bindKey: 'down',
        exec: function (editor) {
            // If the cursor is in the last row.
            if (editor.getCursorPosition().row + 1 === editor.session.getLength()) {
                var value = history.forward();
                if (typeof value === 'string') {
                    editor.setValue(value);
                    editor.navigateFileEnd();
                    editor.navigateLineEnd();
                }
                editor.clearSelection();
            } else {
                editor.navigateDown();
            }
        }
    });

    // Load the history.
    history = new HistoryProvider();
    Bridge.get('get_history').then(function (entries) {
        history.load(entries);
    });

    app.console.addListener('eval', function (text, metadata, promise) {
        if (text != "") {
            promise.then(function (resultAndMetadata) {
                if (resultAndMetadata.metadata.source == metadata.id) {
                    history.push(text);
                    Bridge.call('push_to_history', text);
                }
            }, function (errorMetadata) {
                if (errorMetadata.source == metadata.id) {
                    // TODO
                }
            });
        }
        history.push(text);
    });

});
