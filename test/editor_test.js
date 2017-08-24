requirejs(['qunit', 'jquery', 'lib/editor', 'lib/settings', 'ace/ace', 'lib/bridge_debug_helper', 'lib/bridge'], function (QUnit, $, Editor, Settings, ace, BridgeDebugHelper, Bridge) {

    var aceEditor, settings, editor;

    function doCreateNamedDocument () {
        // Save it under a file name.
        BridgeDebugHelper.mockRequests({ writefile: true });
        return editor.saveAs('filename.txt');
    }

    function doOpenNamedDocument () {
        // Save it under a file name.
        BridgeDebugHelper.mockRequests({ readfile: '' });
        return editor.open('filename.txt');
    }

    function doChangeDocument () {
        aceEditor._emit('change');
    }

    function doCheckDocumentSaved () {
        var status = { saved: false };
        BridgeDebugHelper.mockRequests({
            writefile: function () { return status.saved = true; }
        });
        return status;
    }

    function doCheckExternalChanges () {
        var resolve;
        var promise = new Bridge.Promise(function (resolver, rejector) { resolve = resolver; });
        BridgeDebugHelper.mockRequests({
            observe_external_file_changes: promise
        });
        return {
            doChangeDocument: function () {
                resolve(editor.getCurrentFilepath());
                // Do not reload external version.
                doConfirm('externally', 'Ignore', 0);
            }
        }
    }

    function doConfirm (messageKeyword, buttonLabel, delay) {
        window.setTimeout(function () {
            var confirm = $('.alert:contains(' + messageKeyword + ')');
            var button = confirm.find('button:contains(' + buttonLabel + ')');
            if (button.length != 1) throw('It should prompt to confirm ' + messageKeyword);
            // Confirm
            button.click();
            // Prevent accumulating confirms.
            confirm.remove();
        }, delay);
    }

    QUnit.module('editor', {
        beforeEach: function () {
            $('#qunit-fixture').empty().html('<div id="editorContentWrapper"><div id="editorInput"></div></div>');
            aceEditor = ace.edit('editorInput');
            settings = new Settings();
            editor = new Editor(aceEditor, settings);
        },
    }, function () {

        QUnit.module('checkUnsavedChanges', function () {

            QUnit.test('No unsaved changes', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                // Save it to have no unsaved changes.
                doCreateNamedDocument().then(function () {
                    var status = doCheckDocumentSaved();

                    editor.checkUnsavedChanges().then(function () {
                        assert.notOk(status.saved, 'The document should not be saved');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function () {
                        assert.notOk(status.saved, 'The document should not be saved');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                });
            });

            QUnit.test('Unnamed document, do not save unsaved changes', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var status = doCheckDocumentSaved();
                // Create unsaved changes.
                doChangeDocument();

                editor.checkUnsavedChanges().then(function () {
                    assert.notOk(status.saved, 'The document should not be saved');
                    assert.ok(true, 'The promise should be resolved');
                    done();
                }, function (e) {
                    assert.notOk(status.saved, 'The document should not be saved');
                    assert.ok(false, 'The promise should be resolved');
                    done();
                });
                doConfirm('Save', 'No', 0);
            });

            QUnit.test('Unnamed document, saving cancelled', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var status = doCheckDocumentSaved();
                BridgeDebugHelper.mockRequests({
                    // Cancel the savepanel and reject the request.
                    savepanel: Promise.reject() // TODO: requirejs('promise')
                });
                // Create unsaved changes.
                doChangeDocument();

                editor.checkUnsavedChanges().then(function () {
                    assert.notOk(status.saved, 'The document should not be saved');
                    assert.ok(false, 'The promise should be rejected');
                    done();
                }, function (e) {
                    assert.notOk(status.saved, 'The document should not be saved');
                    assert.ok(true, 'The promise should be rejected');
                    done();
                });
                doConfirm('Save', 'Yes', 0);
            });

            QUnit.test('Unnamed document, save unsaved changes', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var status = doCheckDocumentSaved();
                BridgeDebugHelper.mockRequests({
                    savepanel: 'filename.txt'
                });
                // Create unsaved changes.
                doChangeDocument();

                editor.checkUnsavedChanges().then(function () {
                    assert.ok(status.saved, 'The document should be saved');
                    assert.ok(true, 'The promise should be resolved');
                    done();
                }, function (e) {
                    assert.ok(status.saved, 'The document should be saved');
                    assert.ok(false, 'The promise should be resolved');
                    done();
                });
                doConfirm('Save', 'Yes', 0);
            });

            QUnit.test('Named document, do not save unsaved changes', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                doCreateNamedDocument().then(function () {
                    var status = doCheckDocumentSaved();
                    // Create unsaved changes.
                    doChangeDocument();

                    editor.checkUnsavedChanges().then(function () {
                        assert.notOk(status.saved, 'The document should not be saved');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.notOk(status.saved, 'The document should not be saved');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                    doConfirm('Save', 'No', 0);
                });
            });

            QUnit.test('Named document, save unsaved changes', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                doCreateNamedDocument().then(function () {
                    var status = doCheckDocumentSaved();
                    // Create unsaved changes.
                    doChangeDocument();

                    editor.checkUnsavedChanges().then(function () {
                        assert.ok(status.saved, 'The document should be saved');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.ok(status.saved, 'The document should be saved');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                    doConfirm('Save', 'Yes', 0);
                });
            });

            QUnit.test('Named document, overwrite external changes', function (assert) {
                assert.timeout(3000);
                var done = assert.async(1);

                var external = doCheckExternalChanges();
                BridgeDebugHelper.mockRequests({
                    savepanel: 'filename.txt'
                });
                doOpenNamedDocument().then(function () {
                    var status = doCheckDocumentSaved();
                    // Create unsaved changes.
                    doChangeDocument();
                    external.doChangeDocument();
                    editor.checkUnsavedChanges().then(function () {
                        assert.ok(status.saved, 'The document should be saved');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.ok(status.saved, 'The document should be saved');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                    doConfirm('Save', 'Yes', 100);
                    doConfirm('Overwrite', 'Yes', 200);
                });
            });

            QUnit.test('Named document, do not overwrite external changes, but as new name', function (assert) {
                assert.timeout(3000);
                var done = assert.async(1);

                var external = doCheckExternalChanges();
                BridgeDebugHelper.mockRequests({
                    savepanel: 'filename.txt'
                });
                doOpenNamedDocument().then(function () {
                    var status = doCheckDocumentSaved();
                    // Create unsaved changes.
                    doChangeDocument();
                    external.doChangeDocument();

                    editor.checkUnsavedChanges().then(function () {
                        assert.ok(status.saved, 'The document should be saved');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.ok(status.saved, 'The document should be saved');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                    BridgeDebugHelper.mockRequests({
                        savepanel: 'filename2.txt'
                    });
                    doConfirm('Save', 'Yes', 100);
                    doConfirm('Overwrite', 'No', 200);
                });
            });

            QUnit.test('Named document, do not overwrite external changes, cancelled', function (assert) {
                assert.timeout(3000);
                var done = assert.async(1);

                var external = doCheckExternalChanges();
                BridgeDebugHelper.mockRequests({
                    savepanel: 'filename.txt'
                });
                doOpenNamedDocument().then(function () {
                    var status = doCheckDocumentSaved();
                    // Create unsaved changes.
                    doChangeDocument();
                    external.doChangeDocument();

                    editor.checkUnsavedChanges().then(function () {
                        assert.notOk(status.saved, 'The document should not be saved');
                        assert.ok(false, 'The promise should be rejected');
                        done();
                    }, function (e) {
                        assert.notOk(status.saved, 'The document should not be saved');
                        assert.ok(true, 'The promise should be rejected');
                        done();
                    });
                    BridgeDebugHelper.mockRequests({
                        savepanel: Promise.reject()
                    });
                    doConfirm('Save', 'Yes', 100);
                    doConfirm('Overwrite', 'No', 200);
                });
            });

        });

        QUnit.module('newDocument', function () {

            QUnit.test('Create new document', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                aceEditor.session.setValue('a');
                doCreateNamedDocument().then(function () {

                    editor.newDocument().then(function () {
                        assert.equal(aceEditor.session.getValue(), '', 'The document content should be empty');
                        assert.equal(editor.getCurrentFilepath(), null, 'The current filepath should be reset to null');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.equal(aceEditor.session.getValue(), '', 'The document content should be empty');
                        assert.equal(editor.getCurrentFilepath(), null, 'The current filepath should be reset to null');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                });
            });

            QUnit.test('Fail to create new document', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                aceEditor.session.setValue('a');
                BridgeDebugHelper.mockRequests({
                    writefile: Promise.reject()
                });
                doCreateNamedDocument().then(function () {

                    editor.newDocument().then(function () {
                        assert.equal(aceEditor.session.getValue(), '', 'The document content should be empty');
                        assert.equal(editor.getCurrentFilepath(), null, 'The current filepath should be reset to null');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.equal(aceEditor.session.getValue(), '', 'The document content should be empty');
                        assert.equal(editor.getCurrentFilepath(), null, 'The current filepath should be reset to null');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                });
            });

        });

        QUnit.module('open', function () {

            QUnit.test('Open non-existing file', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var oldContent = 'a';
                aceEditor.session.setValue(oldContent);
                BridgeDebugHelper.mockRequests({
                    readfile: Promise.reject('File does not exist')
                });
                // Save it to have no unsaved changes.
                doCreateNamedDocument().then(function () {
                    var oldFilepath = editor.getCurrentFilepath();

                    editor.open('filename2.txt').then(function () {
                        assert.equal(aceEditor.session.getValue(), oldContent, 'The document should not be changed');
                        assert.equal(editor.getCurrentFilepath(), oldFilepath, 'The current filepath should be preserved');
                        assert.ok(false, 'The promise should be rejected');
                        done();
                    }, function (e) {
                        assert.equal(aceEditor.session.getValue(), oldContent, 'The document should not be changed');
                        assert.equal(editor.getCurrentFilepath(), oldFilepath, 'The current filepath should be preserved');
                        assert.ok(true, 'The promise should be rejected');
                        done();
                    });
                });
            });

            QUnit.test('Open existing file', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var filepath = 'filename.js';
                settings.set('recently_opened_files', []);
                var oldContent = 'a';
                var newContent = 'b';
                aceEditor.session.setValue(oldContent);
                aceEditor.session.setMode('ace/mode/html');
                BridgeDebugHelper.mockRequests({
                    readfile: newContent,
                    observe_external_file_changes: new Promise(function(){})
                });
                // Save it to have no unsaved changes.
                doCreateNamedDocument().then(function () {

                    editor.open(filepath).then(function () {
                        assert.equal(aceEditor.session.getValue(), newContent, 'The document should have the contents of the opened file');
                        assert.equal(editor.getCurrentFilepath(), filepath, 'The current filepath should be set to the opened file');
                        assert.equal(aceEditor.session.$modeId, 'ace/mode/javascript', 'The mode should be set for common file extensions');
                        assert.deepEqual(settings.get('recently_opened_files'), [filepath], 'The filepath should be added to recently opened files');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.equal(aceEditor.session.getValue(), newContent, 'The document should have the contents of the opened file');
                        assert.equal(editor.getCurrentFilepath(), filepath, 'The current filepath should be set to the opened file');
                        assert.equal(aceEditor.session.$modeId, 'ace/mode/javascript', 'The mode should be set for common file extensions');
                        assert.deepEqual(settings.get('recently_opened_files'), [filepath], 'The filepath should be added to recently opened files');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                });
            });

            QUnit.test('Open existing file at line', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var filepath = 'filename.js';
                settings.set('recently_opened_files', []);
                var oldContent = 'a';
                var newContent = 'b\nc\nd\nf';
                var lineNumber = 3;
                aceEditor.session.setValue(oldContent);
                aceEditor.session.setMode('ace/mode/html');
                BridgeDebugHelper.mockRequests({
                    readfile: newContent,
                    observe_external_file_changes: new Promise(function(){})
                });
                // Save it to have no unsaved changes.
                doCreateNamedDocument().then(function () {

                    editor.open(filepath, lineNumber).then(function () {
                        assert.equal(aceEditor.session.getValue(), newContent, 'The document should have the contents of the opened file');
                        assert.equal(editor.getCurrentFilepath(), filepath, 'The current filepath should be set to the opened file');
                        assert.equal(aceEditor.session.$modeId, 'ace/mode/javascript', 'The mode should be set for common file extensions');
                        assert.deepEqual(settings.get('recently_opened_files'), [filepath], 'The filepath should be added to recently opened files');
                        assert.equal(aceEditor.getCursorPosition().row + 1, lineNumber, 'The requested line number should be focussed');
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.equal(aceEditor.session.getValue(), newContent, 'The document should have the contents of the opened file');
                        assert.equal(editor.getCurrentFilepath(), filepath, 'The current filepath should be set to the opened file');
                        assert.equal(aceEditor.session.$modeId, 'ace/mode/javascript', 'The mode should be set for common file extensions');
                        assert.deepEqual(settings.get('recently_opened_files'), [filepath], 'The filepath should be added to recently opened files');
                        assert.equal(aceEditor.getCursorPosition().row + 1, lineNumber, 'The requested line number should be focussed');
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                });
            });

            QUnit.test('Saving unsaved changes cancelled', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var oldFilepath = editor.getCurrentFilepath();
                var oldContent = 'a';
                aceEditor.session.setValue(oldContent);
                BridgeDebugHelper.mockRequests({
                    // Cancel the savepanel and reject the request.
                    savepanel: Promise.reject() // TODO: requirejs('promise')
                });
                // Create unsaved changes.
                doChangeDocument();

                editor.open('filename.txt').then(function () {
                    assert.equal(aceEditor.session.getValue(), oldContent, 'The document should not be changed');
                    assert.equal(editor.getCurrentFilepath(), oldFilepath, 'The current filepath should be preserved');
                    assert.ok(false, 'The promise should be rejected');
                    done();
                }, function (e) {
                    assert.equal(aceEditor.session.getValue(), oldContent, 'The document should not be changed');
                    assert.equal(editor.getCurrentFilepath(), oldFilepath, 'The current filepath should be preserved');
                    assert.ok(true, 'The promise should be rejected');
                    done();
                });
                doConfirm('Save', 'Yes', 0);
            });

        });

        QUnit.module('save', function () {

            QUnit.test('Save', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                // Save it to have no unsaved changes.
                doCreateNamedDocument().then(function () {
                    var currentPath = editor.getCurrentFilepath();
                    var content = aceEditor.session.getValue();
                    var writtenPath, writtenContent;
                    BridgeDebugHelper.mockRequests({
                        writefile: function (filepath, content) {
                            writtenPath = filepath;
                            writtenContent = content;
                            return true;
                        }
                    });

                    editor.save().then(function () {
                        assert.equal(writtenPath, currentPath, 'It should write to the current filepath');
                        assert.equal(editor.getCurrentFilepath(), currentPath, 'The current filepath should remain the same');
                        assert.equal(writtenContent, content, 'The contents of the document should be written to the file');
                        // statusCurrentFileUnsaved and statusCurrentFileExternallyChanged should be set to false
                        assert.ok(true, 'The promise should be resolved');
                        done();
                    }, function (e) {
                        assert.equal(writtenPath, currentPath, 'It should write to the current filepath');
                        assert.equal(editor.getCurrentFilepath(), currentPath, 'The current filepath should remain the same');
                        assert.equal(writtenContent, content, 'The contents of the document should be written to the file');
                        // statusCurrentFileUnsaved and statusCurrentFileExternallyChanged should be set to false
                        assert.ok(false, 'The promise should be resolved');
                        done();
                    });
                });
            });

        });

        QUnit.module('saveAs', function () {

            QUnit.test('Save as and prompt for filepath', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var content = 'a';
                var filepath = 'filename.txt';
                aceEditor.session.setValue(content);
                var writtenPath, writtenContent;
                BridgeDebugHelper.mockRequests({
                    savepanel: filepath,
                    writefile: function (filepath, content) {
                        writtenPath = filepath;
                        writtenContent = content;
                        return true;
                    }
                });

                editor.saveAs().then(function () {
                    assert.equal(writtenPath, filepath, 'It should write to the filepath returned by the savepanel');
                    assert.equal(editor.getCurrentFilepath(), filepath, 'The current filepath should be set to the saved filepath');
                    assert.equal(writtenContent, content, 'The contents of the document should be written to the file');
                    // statusCurrentFileUnsaved and statusCurrentFileExternallyChanged should be set to false
                    assert.ok(true, 'The promise should be resolved');
                    done();
                }, function (e) {
                    assert.equal(writtenPath, filepath, 'It should write to the filepath returned by the savepanel');
                    assert.equal(editor.getCurrentFilepath(), filepath, 'The current filepath should be set to the saved filepath');
                    assert.equal(writtenContent, content, 'The contents of the document should be written to the file');
                    // statusCurrentFileUnsaved and statusCurrentFileExternallyChanged should be set to false
                    assert.ok(false, 'The promise should be resolved');
                    done();
                });
            });

            QUnit.test('Save as and prompt for filepath and cancel', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var content = 'a';
                var filepath = 'filename.txt';
                var previousFilepath = editor.getCurrentFilepath();
                aceEditor.session.setValue(content);
                var writtenPath;
                BridgeDebugHelper.mockRequests({
                    savepanel: Promise.reject(),
                    writefile: function (filepath, content) {
                        writtenPath = filepath;
                        return true;
                    }
                });

                editor.saveAs().then(function () {
                    assert.equal(writtenPath, undefined, 'It should not write to a file');
                    assert.equal(editor.getCurrentFilepath(), previousFilepath, 'The current filepath should be set to the saved filepath');
                    assert.ok(false, 'The promise should be rejected');
                    done();
                }, function (e) {
                    assert.equal(writtenPath, undefined, 'It should not write to a file');
                    assert.equal(editor.getCurrentFilepath(), previousFilepath, 'The current filepath should be set to the saved filepath');
                    assert.ok(true, 'The promise should be rejected');
                    done();
                });
            });

            QUnit.test('Save as with filepath given', function (assert) {
                assert.timeout(1000);
                var done = assert.async(1);
                var content = 'a';
                var filepath = 'filename.txt';
                aceEditor.session.setValue(content);
                var writtenPath, writtenContent;
                BridgeDebugHelper.mockRequests({
                    writefile: function (filepath, content) {
                        writtenPath = filepath;
                        writtenContent = content;
                        return true;
                    }
                });

                editor.saveAs(filepath).then(function () {
                    assert.equal(writtenPath, filepath, 'It should write to the given filepath');
                    assert.equal(editor.getCurrentFilepath(), filepath, 'The current filepath should be set to the saved filepath');
                    assert.equal(writtenContent, content, 'The contents of the document should be written to the file');
                    // statusCurrentFileUnsaved and statusCurrentFileExternallyChanged should be set to false
                    assert.ok(true, 'The promise should be resolved');
                    done();
                }, function (e) {
                    assert.equal(writtenPath, filepath, 'It should write to the given filepath');
                    assert.equal(editor.getCurrentFilepath(), filepath, 'The current filepath should be set to the saved filepath');
                    assert.equal(writtenContent, content, 'The contents of the document should be written to the file');
                    // statusCurrentFileUnsaved and statusCurrentFileExternallyChanged should be set to false
                    assert.ok(false, 'The promise should be resolved');
                    done();
                });
            });

        });

    });
});
