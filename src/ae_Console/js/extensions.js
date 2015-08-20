AE.Console.registerExtension(function(exports) {
    /**
     * ReloadScripts
     * Keeps track of recently loaded scripts and adds them to the reload button.
     * TODO: parts of this are implemented in ui.js, maybe integrate this natively.
     */
    return;

    var tmpID = null; // Cache the id of the last input so it can be matched to its result.
    var tmpPath = ''; // Cache the script path of the last load action so that it can be added when executed successfully.
    var checkboxes = {};
    var menuEntries = {};
    var menu_reload;

    var createMenuEntry = function (path, checked) {
        if (menu_reload) {
            var span = document.createElement('span');
            var label = document.createElement('label');
            var input = document.createElement('input');
            input.setAttribute('type', 'checkbox');
            input.setAttribute('name', path);
            if (checked !== false) {
                input.setAttribute('checked', true);
            }
            input.path = path;
            AE.Events.bind(input, 'click', toggleMenuEntry);
            label.appendChild(input);
            label.appendChild(document.createTextNode(path));
            span.appendChild(label);
            // Button to remove menu entry.
            var closeButton = document.createElement('button');
            closeButton.appendChild(document.createTextNode('×'));
            closeButton.className = 'button_remove right icon';
            closeButton.onclick = function () {
                removeMenuEntry(path);
                updateOptions();
                Bridge.call('stop_observe_file_changed', path);
            };
            span.appendChild(closeButton);
            menu_reload.addItem(span);
            // Remember the item.
            menuEntries[path] = span;
            checkboxes[path] = input;
        }
    };

    var toggleMenuEntry = function () {
        updateOptions();
        if (this.checked) {
            Bridge.call('start_observe_file_changed', this.path);
        } else {
            Bridge.call('stop_observe_file_changed', this.path);
        }
    };

    var removeMenuEntry = function (path) {
        var menu_reload = AE.Console.Menus.getMenu('menu_reload');
        var element = menuEntries[path];
        if (menu_reload && element) {
            menu_reload.removeItem(element);
            delete menuEntries[path];
            delete checkboxes[path];
        }
    };

    var updateOptions = function () {
        var scripts = {};
        for (path in checkboxes) {
            if (path != '') {
                scripts[path] = checkboxes[path].checked;
            }
        }
        Bridge.call('update_options', {reload_scripts: scripts});
    };

    var reload = function () {
        var scripts = [];
        for (path in checkboxes) {
            if (checkboxes.hasOwnProperty(path) && checkboxes[path].checked) {
                scripts.push(path);
            }
        }
        Bridge.call('reload', scripts);
    };

    var scripts = [];
    if (!settings.has('reload_scripts')) settings.set('reload_scripts', scripts);
    /*menu_reload = AE.Console.Menus.getMenu('menu_reload');
    // Add all previous items.
    for (path in Options.reload_scripts) {
        createMenuEntry(path, Options.reload_scripts[path]);
    }
    // Add feature to button,
    AE.Events.bind(AE.$('#button_reload'), 'click', function () {
        AE.Console.editor.focus();
    });*/


    // Test if a script is going to be loaded, then mark it to be added on success.
    exports.console.addListener('input', function (text, metadata) {
        if (/\bload[\(|\s][\"\']([^\"\']+)[\"\']\)?/.test(text)) {
            tmpID = metadata.id;
            tmpPath = RegExp.$1;
        } else {
            tmpID = null;
        }
    });

// TODO: load error handling: gives two errors, should distinguish (file not existing | file exists with error), and try to reload file when modified to fix the error.
    // If the script was loaded successfully, then add it to the menu.
    exports.console.addListener('result', function (text, metadata) {
        if (tmpID == metadata.source && tmpPath !== '') {
            // If it is not yet contained in the menu.
            if (!checkboxes[tmpPath]) {
                createMenuEntry(tmpPath, true);
                updateOptions();
                Bridge.call('start_observe_file_changed', tmpPath);
            }
        }
    });


    exports.console.addListener('error', function (text, metadata) {
        // If the previous input attempted to load a file, it failed.
        tmpID = null;
    });

    /*exports.update = function (hash) {
        var diff = {};
        for (path in menuEntries) {
            diff[path] = menuEntries[path];
        }
        // Update paths from hash.
        for (path in hash) {
            delete diff[path];
            if (path in menuEntries) { // Exists already in this menu
                // Update the checked value
                checkboxes[path].checked = hash[path];
            } else { // Exists not in this menu
                createMenuEntry(path, hash[path]);
            }
        }
        // Remove all others.
        for (path in diff) {
            removeMenuEntry(path);
        }
    };*/
});


AE.Console.registerExtension(function(exports) {
    /**
     * InternalCommands
     * Allows to define internal commands for the console.
     */
    var internalCommands = {
        'js': function (text) {
            exports.settings.set('language', 'javascript');
            //exports.console.aceEditor.session.setMode('ace/mode/javascript');
            AE.Console.puts(AE.Translate.get('Console language changed to "%0"', 'JavaScript'));
            return text;
        },
        'rb': function (text) {
            exports.settings.set('language', 'ruby');
            //exports.console.aceEditor.session.setMode('ace/mode/ruby_sketchup');
            AE.Console.puts(AE.Translate.get('Console language changed to "%0"', 'Ruby'));
            return text;
        },
        'ruby': function (text) {
            exports.settings.set('language', 'ruby');
            //exports.console.aceEditor.session.setMode('ace/mode/ruby_sketchup');
            AE.Console.puts(AE.Translate.get('Console language changed to "%0"', 'Ruby'));
            return text;        },
        'clear': function (text) {
            window.setTimeout(function () {
                exports.console.clearOutput();
            }, 0);
        }
    };
    exports.console.addListener('input', function (text) {
        // Check for internal commands.
        if (text && text[0] === "\\" && text.search(/\n/) === -1) {
            var match = text.slice(1).match(/(\S+)(?:\s+(.+$))?/);
            if (!match) {
                return;
            }
            var command = match[1];
            var arg = match[2]; // the remaining string
            if (command in internalCommands) {
                // If null returned, normal evaluation does not happen.
                // If string is returned, it will be evaluated.
                return internalCommands[command].call(window, arg) || "";
            }
        }
    });
});


AE.Console.registerExtension(function(exports) {
    /**
     * History
     * Allows to navigate back to previous input.
     */
    var history;
    var tmpID = null; // Cache the id of the last input so it can be matched to its result.
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
            data = [];// TODO: replace by our abstract data structure (priority queue + queue)

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
            /*// Check if the long memory is exceeded.
            if (data.length > MAX_LENGTH) {
                data.shift();
            }
            // Check if the short memory needs to be cleared.
            if (shortMemoryPos >= shortMemoryLength) {
                data.splice(data.length - shortMemoryPos - 1, 1);
                shortMemoryPos = -1;
            }
            var l = data.length;
            // Don't add a new item to the stack if it's identical to the n-th
            // previous item.
            // n = 0: No change.
            if (value === data[l - 0 - 1]) {
                return;
                // 0 < n < reorderLength: Change the order.
            } else {
                          for (var n = 1; n < reorderLength; n++) {
                 if (l >= n+1 && value === data[l-n-1]) {
                 data.splice(l-n-1, 1);
                 data.push(value);
                 // Update the index for the short memory.
                 if (shortMemoryPos != -1 && shortMemoryPos < n) { shortMemoryPos++; }
                 else if (shortMemoryPos == n) { shortMemoryPos = 0; }
                 return;
                 }
                 }
                // reorderLength < n < Infinity: Add the new item.
                data.push(value);
                          if (shortMemoryPos != -1) { shortMemoryPos++; }
                return;
            }*/
        };

        /*// Add an item temporarily into "shortMemory".
        // It will be overwritten after 'shortMemoryLength' pushes.
        this.tmp = function (value) {
            selected = 0;
            if (shortMemoryPos != -1) {
                data.splice(data.length - shortMemoryPos - 1, 1);
            }
            history.push(value);
            shortMemoryPos = 0;
        };*/

    }; // end class HistoryProvider


    // Load the history.
    history = new HistoryProvider();
    Bridge.get('get_history').then(function (entries) {
        history.load(entries);
    });

    exports.console.addListener('arrowUp', function (editor) {
        var value = history.back(editor.getValue());
        if (typeof value === 'string') {
            editor.setValue(value);
            editor.navigateFileStart();
            editor.navigateLineEnd();
        }
        editor.clearSelection();
    });

    exports.console.addListener('arrowDown', function (editor) {
        var value = history.forward();
        if (typeof value === 'string') {
            editor.setValue(value);
            editor.navigateFileEnd();
            editor.navigateLineEnd();
        }
        editor.clearSelection();
    });

    exports.console.addListener('input', function (text, metadata) {
        /*tmpID = metadata.id;
        tmpInput = text;*/
        history.push(text);
    });

    // TODO: Can we use promises to execute actions on result of console evaluation?
    // Like: console.submit returns promise?
    // event input has parameter promise, is resolved when evaluation gives result or error

    /*exports.onResult = function (text, metadata) {
        if (metadata.source == tmpID && tmpInput !== "") {
            history.push(tmpInput);
        }
    };

    // We don't want to remember incorrect input permanently, because it
    // is not useful and would cause an error again. But we keep it for
    // a moment until the user corrects it.
    // TODO: better design for this use case
    exports.onError = function (text, metadata) {
        if (metadata.source == tmpID && tmpInput !== "") {
            history.push(tmpInput);
        }
    };*/

});

/*
AE.Console.Extensions.register({
    name: 'DynamicToolbar',
    description: 'A dynamic toolbar with useful features in the output field.',
    enabled: true,
    content: function (exports) {
        exports.onLoad = function () {
            // Add a CSS rule.
            AE.Style.setRule('.dynamic_toolbar', {
                display: 'block',
                position: 'absolute',
                "z-index": 1000,
                right: 0,
                "vertical-align": 'middle'
            });
            AE.Style.setRule('.dynamic_toolbar button img', {
                width: '1em',
                height: '1em'
            });
        };

        exports.onCodeAdded = function (div, text, metadata) {
            var toolbar = document.createElement('div');
            toolbar.className = 'dynamic_toolbar';
            toolbar.style.display = 'none';
            toolbar.style.position = 'absolute';
            toolbar.style.top = 0;
            toolbar.style.right = 0;
            // A button to repeat a command.
            if (metadata.type && /input/.test(metadata.type)) {
                var button_repeat = document.createElement('button');
                var icon_repeat = document.createElement('img');
                icon_repeat.src = '../images/icon_repeat.png';
                button_repeat.title = icon_repeat.alt = AE.Translate.get('Repeat');
                button_repeat.appendChild(icon_repeat);
                toolbar.appendChild(button_repeat);
                button_repeat.onclick = function () {
                    AE.Console.editor.setValue(div.text);
                    AE.Console.editor.clearSelection();
                    AE.Console.editor.focus();
                };
                button_repeat.ondblclick = function () {
                    AE.Console.editor.setValue(div.text);
                    window.setTimeout(function () {
                        AE.Console.editor.submit(div.text);
                        AE.Console.editor.focus();
                    }, 100);
                };
            }
            // A button to select an item.
            //var button_select = document.createElement("button");
            //var icon_select = document.createElement("img");
            //icon_select.src = "../images/icon_select.png";
            //button_select.title = icon_select.alt = AE.Translate.get("Select");
            //button_select.appendChild(icon_select);
            //toolbar.appendChild(button_select);
            //button_select.onclick = function() {
            // TODO: Select the code.
            //}
            // A button to remove an item from the output.
            var button_remove = document.createElement('button');
            var icon_remove = document.createElement('img');
            icon_remove.src = '../images/icon_remove.png';
            button_remove.title = icon_remove.alt = AE.Translate.get('Remove');
            button_remove.appendChild(icon_remove);
            toolbar.appendChild(button_remove);
            button_remove.onclick = function () {
                toolbar.parentNode.parentNode.removeChild(div);
                AE.Console.editor.focus();
            };
            // A button to remove all newer items from the output.
            var button_remove_down = document.createElement('button');
            var icon_remove_down = document.createElement('img');
            icon_remove_down.src = '../images/icon_remove_down.png';
            button_remove_down.title = icon_remove_down.alt = AE.Translate.get('Remove all downwards');
            button_remove_down.appendChild(icon_remove_down);
            toolbar.appendChild(button_remove_down);
            button_remove_down.onclick = function () {
                while (div.nextSibling) {
                    toolbar.parentNode.parentNode.removeChild(div.nextSibling);
                }
                toolbar.parentNode.parentNode.removeChild(div);
                AE.Console.editor.focus();
            };
            //
            div.appendChild(toolbar);
            toolbar.timer = null;
            AE.Events.bind(div, 'mouseover', function () {
                window.clearTimeout(toolbar.timer);
                toolbar.timer = window.setTimeout(function () {
                    AE.Style.show(toolbar);
                }, 500);
            });
            AE.Events.bind(div, 'mouseout', function () {
                window.clearTimeout(toolbar.timer);
                toolbar.timer = window.setTimeout(function () {
                    AE.Style.hide(toolbar);
                }, 500);
            });
        };
    }
});*/


AE.Console.registerExtension(function(exports) {
    /**
     * HighlightEntity
     * This highlights SketchUp entities and points and colors when hovering the console.
     */

    // Add a CSS rule.
    var className = 'highlight_entity';
    AE.Style.setRule('.' + className, { // TODO: refactor Style.setRule()
        border: '1px solid lightgray',
        display: 'inline-block'
    });
    AE.Style.setRule('.' + className + ':hover', {
        color: 'Highlight',
        'border-color': 'Highlight'
    });
    function stop () {
        Bridge.call('highlight_stop');
    }
    var regexpEntity       = /#(?:<|&lt;|&#60;)Sketchup\:\:(?:Face|Edge|Curve|ArcCurve|Image|Group|ComponentInstance|ComponentDefinition|Text|Drawingelement|ConstructionLine|ConstructionPoint|Vertex)\:([0-9abcdefx]+)(?:>|&gt;|&#62;)/,
        regexpBoundingBox  = /#(?:<|&lt;|&#60;)Geom\:\:(?:BoundingBox)\:([0-9abcdefx]+)(?:>|&gt;|&#62;)/,
        regexpPoint        = /Point3d\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpPointString  = /(?!Point3d)\(([0-9\.\,\-eE]+)(?:m|\"|\'|cm|mm),[\s\u00a0]*([0-9\.\,\-eE]+)(?:m|\"|\'|cm|mm),[\s\u00a0]*([0-9\.\,\-eE]+)(m|\"|\'|cm|mm)\)/,
        regexpVector       = /Vector3d\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpVectorString = /\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpColor        = /Color\(([\s\u00a0]*[0-9\.]+,[\s\u00a0]*[0-9\.]+,[\s\u00a0]*[0-9\.]+)(,[\s\u00a0]*[0-9\.]+)?\)/;
    exports.output.addListener('afterCodeAdded', function (htmlElement, metadata) {
        if (metadata.type && /input|result|puts|print/.test(metadata.type) && !/javascript/.test(metadata.type)) {
            $(htmlElement).find('.ace_sketchup').each(function(index, element){
                var $element = $(element);
                var text = $element.text();
                if (regexpEntity.test(text) || regexpBoundingBox.test(text)) {
                    // Add highlight feature to SketchUp entities and get their id (which is for some reason 2 * the Ruby object_id)
                    var id = parseInt(RegExp.$1) >> 1;
                    $element.addClass(className)
                        .on('mouseover', function() {
                            Bridge.get('highlight_entity', id)['catch'](function () {
                                // If the entity isn't valid (deleted or GC), remove the highlight feature.
                                $element.removeClass(className);
                                $element.off('mouseover');
                                $element.off('mouseout');
                            });
                        }).on('mouseout', stop);
                } else if (regexpPoint.test(text)) {
                    // Add highlight feature to Point3d (without units: inch = " = \u0022 )
                    var coordinates = [parseFloat(RegExp.$1), parseFloat(RegExp.$2), parseFloat(RegExp.$3)];
                    $element.addClass(className)
                        .on('mouseover', function() {
                            Bridge.call('highlight_point', coordinates);
                        }).on('mouseout', stop);
                } else if (regexpPointString.test(text)) {
                    // Add highlight feature to Point3d string
                    var coordinates = $([RegExp.$1, RegExp.$2, RegExp.$3]).map(function(coordinate){
                        return parseFloat(coordinate.replace(/\,(?=[\d])/, '.'));
                    });
                    var units = RegExp.$4;
                    // Replace unit names so they don't need escaping.
                    switch (units) {
                        case '"':
                            units = 'inch';
                            break;
                        case "'":
                            units = 'feet';
                            break;
                    }
                    $element.addClass(className)
                        .on('mouseover', function() {
                            Bridge.call('highlight_point', coordinates, units);
                        }).on('mouseout', stop);
                } else if (regexpVector.test(text) || regexpVectorString.test(text)) {
                    // Add highlight feature to Vector3d or Vector3d string
                    var coordinates = [parseFloat(RegExp.$1), parseFloat(RegExp.$2), parseFloat(RegExp.$3)];
                    $element.addClass(className)
                        .on('mouseover', function() {
                            Bridge.call('highlight_vector', coordinates);
                        }).on('mouseout', stop);
                } else if (regexpColor.test(text)) {
                    var color = 'rgb(' + RegExp.$1 + ')';
                    $element.addClass(className)
                        .on('mouseover', function() {
                            $(this).css('background-color', color);
                        }).on('mouseout', function() {
                            $(this).css('background-color', 'none');
                        });
                }
            });
        }
    });

    /**
     * ReportModifierKeys
     * Allows the SketchUp main window to see modifier keys pressed when the webdialog has focus.
     */
    $(document).on('keydown', function (event) {
        if (event.shiftKey || event.ctrlKey || event.altKey) {
            var keys = {
                shift: event.shiftKey,
                ctrl:  event.ctrlKey,
                alt:   event.altKey
            };
            Bridge.call('modifier_keys', keys);
        }
    });
    $(document).on('keyup', function (event) {
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
    });
});



/*


// TODO: is it possible to detect when an operation is not needed?
// Like: Detect when no changes to entities occur? Regexp search for Ruby API
// method names that modify entities.
AE.Console.Extensions.register({
    name: 'WrapInUndo',
    description: 'Wrap every code execution into an undo operation. \
    This allows you to revert changes to SketchUp entities',
    enabled: true,
    content: function (exports) {
        exports.onLoad = function (Options) {
            var item = document.createElement('label');
            var checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.name = 'wrap_in_undo';
            checkbox.checked = Options.wrap_in_undo || false;
            item.appendChild(checkbox);
            item.appendChild(document.createTextNode(AE.Translate.get('Wrap in undoable operation')));
            AE.Console.Menus.getMenu('preferences').addItem(item);

            AE.Events.bind(checkbox, 'change', function () {
                Bridge.call("update_options", {wrap_in_undo: checkbox.checked});
            });
            AE.Events.bind(checkbox, 'click', function () {
                Bridge.call('update_options', {wrap_in_undo: checkbox.checked});
            });
        };
    }
});


AE.Console.Extensions.register({
    name: 'Autocompleter',
    description: 'Suggests autocompletions.',
    enabled: true,
    content: function (exports) {
        var runtimeCompleter = {
            getCompletions: function (editor, session, pos, prefix, callback) {
                var tokens = AE.Console.getCurrentTokenList(session, pos);
                // Allows us to do corrections if ace splits tokens incorrectly. We can pass the corrected prefix to
                // Ruby, but ace would replace the incomplete prefix by the corrected one and lead to duplication.
                // We later subtract the correction from the completions.
                var subtract = null;
                var last = tokens[tokens.length-1];
                var missingPrefixes = ['@@', '@', ''];
                for (var i = 0; i < missingPrefixes.length; i++) {
                    var prefix2 = missingPrefixes[i];
                    if (last == prefix2 + prefix) {
                        prefix = prefix2 + prefix;
                        subtract = prefix2;
                        tokens.pop();
                        break;
                    }
                }
                // Query SketchUp for completions.
                // if (tokens.length == 0) textCompleter.getCompletions(editor, session, pos, prefix, callback);
                Bridge.get('autocomplete_token_list', prefix, tokens).then(function (completions) {
                    try{
                        for (var i = 0; i < completions.length; i++) {
                            if (subtract) completions[i].value = completions[i].value.substring(subtract.length);
                        }
                    } catch(e) {Bridge.error(e);}
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
        var textCompleter;

        exports.onLoad = function (Options) {
            // Enable autocompletion
            ace.config.loadModule('ace/ext/language_tools', function (language_tools) {
                var editor = AE.Console.editor;
                editor.setOptions({
                    enableBasicAutocompletion: true,
                    enableLiveAutocompletion: true
                    //enableSnippets: true
                });
                // Patch: By default, ace autocomplete listens for the enter key (Return, among Shift-Return and Tab).
                // This conflicts with the use as a console, because enter should submit and execute the code.
                var Autocomplete = ace.require('ace/autocomplete').Autocomplete;
                Autocomplete.prototype.commands.Return = function() {
                    // If live autocompletion is on and the first autoselected completion is selected, we cancel and
                    // let the console handle enter to submit and execute the code.
                    if (editor.getOption('enableLiveAutocompletion') && editor.completer.popup.getRow() == 0) {
                        editor.completer.detach();
                        // Allow bubbling of the Return key event, so the default action (Console submit) is
                        return false;
                    } else {
                        // If a lower completion has been selected (intentionally), we allow enter to accept it.
                        editor.completer.insertMatch();
                    }
                };
                // As of ace 1.1.2, the built-in completers are: (ext-language_tools line 69)
                // [snippetCompleter, textCompleter, keyWordCompleter]
                // They return too many irrelevant results, even worse due to the fuzzy filter,
                // so we want to keep only the snippetCompleter.
                editor.completers.pop();
                textCompleter = editor.completers.pop();
                // And we add a runtimeCompleter that queries completions from Ruby's introspection methods.
                language_tools.addCompleter(runtimeCompleter);
            });
        };
    }
});


AE.Console.Extensions.register({
    name: 'DocumentationBrowser',
    description: 'Opens a browser window with relevant documentation.',
    enabled: true,
    content: function (exports) {
        exports.onLoad = function (Options) {
            var command = function () {
                var session = AE.Console.editor.getSession();
                var pos = AE.Console.editor.getCursorPosition();
                var tokens = AE.Console.getCurrentTokenList(session, pos);
                Bridge.call('open_help', tokens);
            };
            AE.Console.editor.commands.addCommand({
                name: AE.Translate.get('Show documentation for the currently focussed word in a browser window.'),
                bindKey: 'Ctrl-Q',
                exec: command
            });

            var button = AE.$('#button_help');
            AE.Events.bind(button, 'click', command);
        };
    }
});
*/
