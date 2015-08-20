var AE = window.AE || {};

AE.Console = AE.Console || {};

AE.Console.Editor = function(aceEditor, settings) {

    var editor = this,
        currentFilepath,
        currentFiletype,
        statusCurrentFileUnsaved = false,// TODO: on edit: true; on open new file: false; on save: false; on undo to last step: true
        modes = {
            '.rb':   'ace/mode/ruby_sketchup',
            '.css' : 'ace/mode/css',
            '.html': 'ace/mode/html',
            '.htm':  'ace/mode/html',
            '.js':   'ace/mode/javascript',
            '.json': 'ace/mode/json'
        };

    function initialize () {
        configureAce(aceEditor);

        // Listen for changes in the document to keep the (un)saved status variable up-to-date.
        // TODO: Test!
        aceEditor.on('change', function(){ // TODO: ? aceEditor.getSession(),  aceEditor.getSession().getDocument().on
            statusCurrentFileUnsaved = true;
        });
    }

    // Implementation of Observer/Observable

    this.addListener = function (eventName, fn) {
        $(editor).on(eventName, function (event, args) {
            fn.apply(undefined, args);
        });
    };

    function trigger (eventName, data) {
        var args = Array.prototype.slice.call(arguments).slice(1);
        $(editor).trigger(eventName, [args]);
    }

    function configureAce(aceEditor) {
    }

    function confirmSaveChanges() {
        return window.confirm(AE.Translate.get('Save changes to current file?'));
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

    this.newDocument = function () {
        // Ask whether to save changes if there are unsaved changes.
        if (statusCurrentFileUnsaved && confirmSaveChanges()) {
            return editor.save().then(function() {
                return editor.newDocument();
            });
        } else {
            editor.setContent('');
            currentFilepath = null;
            // Leave the current mode (or set it to plain text or ruby?)
            // Since the file is new, it has not been saved yet.
            statusCurrentFileUnsaved = true;
            return new Bridge.Promise.resolve('');
        }
    };

    this.open = function (filepath) {
        // Ask whether to save changes if there are unsaved changes.
        if (statusCurrentFileUnsaved && confirmSaveChanges()) {
            return editor.save().then(function() {
                return editor.open(filepath);
            });
        } else {
            // Read the file and load its content into the ace editor.
            return Bridge.get('readfile', filepath).then(function (content) {
                editor.setContent(content);
                currentFilepath = filepath;
                // Try to determine the ace mode from the file name.
                var extensionMatch = filepath.match(/\.\w{1,3}$/i);
                if (extensionMatch && extensionMatch[0]) {
                    currentFiletype = extensionMatch[0].toLowerCase();
                    aceEditor.session.setMode(modes[currentFiletype] || 'ace/mode/text');
                } else {
                    currentFiletype = undefined;
                    aceEditor.session.setMode('ace/mode/text');
                }
                // Since the file has just been loaded, it has no unsaved changes yet.
                statusCurrentFileUnsaved = false;
            }, function (error) {
                // notification: File failed to open
                window.alert('Failed to open file "' + filepath + '": \n' + error);
            });
        }
    };

    this.save = function () {
        // Ask where to save the file if no file path is associated.
        if (typeof currentFilepath !== 'string') {
            return editor.saveAs();
        } else {
            // Write the content to the file.
            return Bridge.get('writefile', filepath, editor.getContent()).then(function () {
                // success
                // The file has been saved successfully, so there are no unsaved changes anymore.
                statusCurrentFileUnsaved = false;
            }, function (error) {
                // error notification
                window.alert('Failed to save file "' + currentFilepath + '": \n' + error);
            });
        }
    };

    this.saveAs = function () {
        // Ask where to save the file.
        return Bridge.get('savepanel', AE.Translate.get('Save the file as…')).then(function (filepath) {
            currentFilepath = filepath;
            return editor.save();
        });
    };

    initialize();
};