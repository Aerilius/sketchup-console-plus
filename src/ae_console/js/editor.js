define(['jquery', 'bootstrap-notify', './bridge', './translate'], function ($, _, Bridge, Translate) {
    return function (aceEditor, settings) {

        var editor = this,
            currentFilepath = null,
            currentFiletype = null,
            statusCurrentFileUnsaved = false,
            statusCurrentFileExternallyChanged = false,
            modes = {
                '.rb':   'ace/mode/ruby_sketchup',
                '.css' : 'ace/mode/css',
                '.html': 'ace/mode/html',
                '.htm':  'ace/mode/html',
                '.js':   'ace/mode/javascript',
                '.json': 'ace/mode/json'
            };
        this.aceEditor = aceEditor;

        function initialize () {
            configureAce(aceEditor);
            // Listen for changes in the document to keep the (un)saved status variable up-to-date.
            aceEditor.on('change', function(){
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

        this.focus = function () {
            aceEditor.focus();
        };

        this.setContent = function (content) {
            aceEditor.session.setValue(content);
        };

        this.getContent = function () {
            return aceEditor.session.getValue();
        };

        this.getCurrentFilepath = function () {
            return currentFilepath;
        };

        /**
         * Checks whether there are unsaved changes and asks the user whether to save.
         * Ensures that afterwards the document can be savely closed/changed/replaced.
         * The promise will be resolved if:
         *   - There are no unsaved changes.
         *   - The user wants to disgard changes.
         *   - The user wants to save changes and saving has succeeded.
         * It will be rejected if:
         *   - Saving failed, e.g. the user changed his opinion and cancelled the save dialog.
         * @returns {Promise}
         */
        /*
        if ((statusCurrentFileUnsaved && confirmSaveChanges()) && (!statusCurrentFileExternallyChanged || confirmSaveAndIgnoreExternalChanges())) {
            return editor.save();
        } else {
            return Bridge.Promise.resolve(true);
        }
         */
        this.checkUnsavedChanges = function () {
            // Ask whether to save changes if there are unsaved changes.
            if (statusCurrentFileUnsaved) {
                return confirmSaveChanges().then(function checkExternalChangeAndConfirm () {
                    if (!statusCurrentFileExternallyChanged) {
                        return editor.save();
                    } else {
                        return confirmSaveAndIgnoreExternalChanges().then(editor.save, /*else*/ editor.saveAs);
                    }
                }, /*else*/ function () {
                    return Bridge.Promise.resolve(true);
                });
            } else {
                return Bridge.Promise.resolve(true); // Return a resolved promise
            }
        };

        this.newDocument = function () {
            // Ask whether to save changes if there are unsaved changes.
            return this.checkUnsavedChanges().then(function doNewDocument () {
                if (currentFilepath) closeCurrentFile();
                editor.setContent('');
                currentFilepath = null;
                // Set the mode to plain text or ruby or leave the current mode.
                // aceEditor.session.setMode('ace/mode/text');
                // Since the file is new, it has not been saved yet.
                statusCurrentFileUnsaved = true;
                statusCurrentFileExternallyChanged = false;
                // Trigger an event.
                trigger('opened', '');
                return true;
            });
        };

        this.open = function (filepath, lineNumber) {
            // Do not load the file again if it is already opened.
            if (filepath == currentFilepath) {
                if (lineNumber) aceEditor.gotoLine(lineNumber);
                return Bridge.Promise.resolve(true); // Return a resolved promise
            }
            // Ask whether to save changes if there are unsaved changes.
            return this.checkUnsavedChanges().then(function doOpen () {
                if (currentFilepath) closeCurrentFile();
                // Read the file and load its content into the ace editor.
                return loadFile(filepath).then(function () {
                    addToRecentlyOpenedFiles(filepath);
                    // Try to determine the ace mode from the file name.
                    var extensionMatch = filepath.match(/\.\w{1,3}$/i);
                    if (extensionMatch && extensionMatch[0]) {
                        currentFiletype = extensionMatch[0].toLowerCase();
                        aceEditor.session.setMode(modes[currentFiletype] || 'ace/mode/text');
                    } else {
                        currentFiletype = undefined;
                        aceEditor.session.setMode('ace/mode/text');
                    }
                    // Try to jump to the line number where the file was last accessed.
                    if (!lineNumber) lineNumber = settings.get('recently_focused_lines', {})[filepath] || 1;
                    aceEditor.gotoLine(lineNumber); // one-based
                }, function (error) {
                    // notification: File failed to open
                    alert('Failed to open file "' + filepath + '": \n' + error);
                    throw error;
                });
            });
        };

        this.save = function () {
            // Ask where to save the file if no file path is associated.
            if (typeof currentFilepath !== 'string') {
                return editor.saveAs();
            } else {
                // Write the content to the file.
                return Bridge.get('writefile', currentFilepath, editor.getContent()).then(function () {
                    // success
                    // The file has been saved successfully, so there are no unsaved changes anymore.
                    statusCurrentFileUnsaved = false;
                    statusCurrentFileExternallyChanged = false;
                    // Trigger an event.
                    trigger('saved', currentFilepath);
                }, function (error) {
                    // error notification
                    alert(Translate.get('Failed to save file') + ' "' + currentFilepath + '": \n' + error);
                });
            }
        };

        this.saveAs = function (filepath) {
            if (typeof filepath !== 'string') {
                // Ask where to save the file.
                return Bridge.get('savepanel', Translate.get('Save the current file as…'), currentFilepath).then(function (filepath) {
                    currentFilepath = filepath;
                    return editor.save();
                });
            } else {
                currentFilepath = filepath;
                return editor.save();
            }
        };

        function configureAce (aceEditor) {
            // Set the mode to Ruby.
            aceEditor.session.setMode('ace/mode/ruby_sketchup');
        }

        function alert (message, type) {
            var notify = $.notify(message, {
                type: type || 'danger',
                element: $('#editorContentWrapper'),
                placement: { from: 'top', align: 'center' },
                offset: { x: 0, y: 0 },
                allow_dismiss: true
            });
        }

        function confirm (message, action1, action2) {
            return new Bridge.Promise(function (resolve, reject) {
                var notify = $.notify('', {
                    type: 'warning',
                    element: $('#editorContentWrapper'), // TODO: Remove binding to a specific HTML element.
                    placement: { from: 'top', align: 'center' },
                    offset: { x: 0, y: 0 },
                    allow_dismiss: true,
                    delay: 0,
                    template: '<div data-notify="container" class="col-sm-3 alert alert-{0}" role="alert"><span data-notify="message">' +
                        Translate.get(message) + '&nbsp;<button class="notify_button_action1" style="min-width: 4em">' +
                        Translate.get(action1 || 'Yes') + '</button>&nbsp;<button type="button" class="notify_button_action2" style="min-width: 4em">' +
                        Translate.get(action2 || 'No') + '</button></span></div>'
                });
                $('.notify_button_action1', notify.$ele).on('click', function() {
                    notify.close();
                    resolve();
                });
                $('.notify_button_action2', notify.$ele).on('click', function() {
                    notify.close();
                    reject();
                });
            });
        }

        function confirmSaveChanges () {
            return confirm('Save changes to current file?');
        }

        function confirmSaveAndIgnoreExternalChanges () {
            return confirm('The file has been changed externally.\nOverwrite external changes and save the current file?');
        }

        function addToRecentlyOpenedFiles (filepath) {
            var recentlyOpened = settings.get('recently_opened_files', []);
            var index = recentlyOpened.indexOf(filepath);
            if (index != -1) recentlyOpened.splice(index, 1);
            if (index !=  0) recentlyOpened.unshift(filepath);
            if (recentlyOpened.length > 10) recentlyOpened.length = 10;
            settings.set('recently_opened_files', recentlyOpened);
        }

        function loadFile (filepath) {
            if (!filepath) filepath = currentFilepath;
            return Bridge.get('readfile', filepath).then(function (content) {
                editor.setContent(content);
                // Since the file has just been loaded, it has no unsaved changes yet.
                statusCurrentFileUnsaved = false;
                statusCurrentFileExternallyChanged = false;
                currentFilepath = filepath;
                // Notify on external changes of the just opened file.
                Bridge.get('observe_external_file_changes', filepath).then(function (path) {
                    if (path == filepath) {
                        statusCurrentFileExternallyChanged = true;
                        confirm('The file was changed externally.', 'Reload', 'Ignore')
                        .then(loadFile);
                    }
                });
                // Trigger an event.
                trigger('opened', filepath);
            });
        }

        function closeCurrentFile () {
            if (currentFilepath) {
                // Remember the currently focused line for this file.
                var lineNumber = aceEditor.getCursorPosition().row; // zero-based
                var recentlyFocusedLines = settings.get('recently_focused_lines', {});
                recentlyFocusedLines[currentFilepath] = lineNumber+1;
                settings.set('recently_focused_lines', recentlyFocusedLines); // Using the set function to trigger saving.
            }
        }

        initialize();
    };
});
