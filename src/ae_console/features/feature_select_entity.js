requirejs(['app', 'bridge', 'translate'], function (app, Bridge, Translate) {
    /**
     * Register events on toolbar button.
     * Note: Toolbar button is specified in HTML, there is no API yet to do it in this script.
     */
    var aceEditor = app.console.aceEditor;
    var toolActive = false;
    $('#buttonConsoleSelect').attr('title', Translate.get('Click to select an entity. Right-click to abort. Press the ctrl key to select points. Press the shift key to use inferencing.'));
    $('#buttonConsoleSelect').on('click', function () {
        var selectionRange = aceEditor.getSelectionRange();
        var selectedText   = aceEditor.session.getTextRange(selectionRange);
        toolActive = true;
        Bridge.get('select_entity', selectedText).then(function (name) {
            // Entity was selected and referenced by a variable with this name.
            aceEditor.getSession().getDocument().replace(selectionRange, name);
            window.focus();
            aceEditor.focus();
        }, function() {
            // Tool was cancelled.
            toolActive = false;
        });
    });
    
    /**
     * ReportModifierKeys
     * Allows the SketchUp main window to see modifier keys pressed when the webdialog has focus.
     */
    $(document).on('keydown', function (event) {
        if (toolActive) {
            if (event.shiftKey || event.ctrlKey || event.altKey) {
                var keys = {
                    shift: event.shiftKey,
                    ctrl:  event.ctrlKey,
                    alt:   event.altKey
                };
                Bridge.call('modifier_keys', keys);
            }
        }
    });
    $(document).on('keyup', function (event) {
        if (toolActive) {
            // Is the keycode of the key that triggered the event equal to shift, ctrl, alt?
            if (!(event.keyCode == 16 || event.keyCode == 17 || event.keyCode == 18)) {
            } else {
                // Then get the current status of the keys:
                var keys = {
                    shift: event.shiftKey,
                    ctrl:  event.ctrlKey,
                    alt:   event.altKey
                };
                Bridge.call('modifier_keys', keys);
            }
        }
    });
});
