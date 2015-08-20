// requires Base.js
var AE = window.AE || {};
/*
 These lines in ace 1.1.2 needed to be patched to suppress errors:
 • ace.js line 2104 (Chromium): "this.textInput undefined"
 • ace.js line 4474: "Could not complete the operation due to error 80020003."
 • ace.js line 5652: "'value.length' is null or not an object"
 • ace.js line 11111: "'length' is null or not an object"
 • ace.js line 13744: "cssClass is null or not an object"
 • ace.js line 14745: "'undefined' is null or not an object"
 • ace.js line 14762: "'undefined' is null or not an object"
 • ace.js line 14794: "'length' is null or not an object"
 • ace.js line 14797: "'length' is null or not an object"
 This line might need to be patched also:
 • ext-searchbox.js line 252: "e = window.event"
 This error might happen:
 • ace.js (line 4339): Could not complete the operation due to error 80020003.
 Apart from that, ace needs IE to be run in the (latest) mode that is installed,
 that means IE=edge.
 */
/* In ace 1.2.0 I have so far only patched:
 • ext-language_tools line 1590:
     In IE8, tooltipNode would default to have HTMLDocument as parent and not be displayed.
     Make sure it is appended to body:
     if (!tooltipNode.parentNode || tooltipNode.parentNode != document.body)
*/


/**
 * @module
 */
AE.Console = function (self) {

self.setText=function(s){self.editor.session.setValue(s);}; // TODO: debug
    /**
     * Object to hold options.
     * @var {object<string, JSONObject>}
     */
    var Options = self.Options = {
        show_time: false,
        wrap_lines: false,
        verbosity: null,
        language: 'ruby', // or "javascript"
        theme: 'ace/theme/chrome',
        binding: 'global'
    };


    var editor, output, history,
        console_id = 'js:',
        message_id = 0,
        binding_element,
        verbosity_element,
        wrap_lines_element,
        show_time_element;


    /**
     * Add input to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    self.input = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'input';
        Extensions.trigger('onInput', text, metadata);
        if (output) {
            output.add(text, metadata);
        }
    };


    /**
     * Add a return value to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    self.result = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'result';
        Extensions.trigger('onResult', text, metadata);
        if (output) {
            output.add(text, metadata);
        }
    };


    /**
     * Add an error to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    self.error = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'error';
        Extensions.trigger('onError', text, metadata);
        if (output) {
            output.add(text, metadata);
        }
    };


    /**
     * Add a warning to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    self.warn = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'warn';
        Extensions.trigger('onWarn', text, metadata);
        if (output) {
            output.add(text, metadata);
        }
    };


    /**
     * Add a JavaScript error to the output.
     * @param {Error} error
     */
    self.javaScriptError = function (error) {
        if (error.number) {
            error.lineNumber = error.number;
        }
        if (error.fileName == window.location.href && error.lineNumber == 1) {
            error.fileName = '(eval)';
        }
        var backtrace = (error.fileName) ?
            [
                decodeURIComponent(
                    error.fileName.replace(/^file\:\/\/(\/(?=\w\:))?/, "")
                ) + ": " + error.lineNumber
            ] : [];
        AE.Console.error('(JavaScript) ' + error.name + ": " + error.message,
            {language: 'javascript', backtrace: backtrace});
    };


    /**
     * Add puts stdout to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    self.puts = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'puts';
        Extensions.trigger('onPuts', text, metadata);
        if (output) {
            output.add(text, metadata);
        }
    };


    /**
     * Add print stdout to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    self.print = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'print';
        Extensions.trigger('onPrint', text, metadata);
        if (output) {
            output.add(text, metadata);
        }
    };


    /**
     * Initialize the UI.
     */
    self.initialize = function () {
        /* INPUT FIELD */

        // Hack to hide the scrollbar.
        ace.require('ace/lib/dom').scrollbarWidth = function (document) {
            return 0;
        };

        // Create the ace editor. // TODO: This does not get called in WE because ace loads incompletely.
        editor = self.editor = ace.edit('input');

        // Add default settings.
        editor.setDisplayIndentGuides(true);
        editor.setHighlightActiveLine(true);
        editor.setHighlightSelectedWord(true);
        editor.setSelectionStyle('line');
        editor.setShowInvisibles(true);
        editor.renderer.setShowGutter(true);
        editor.renderer.setShowPrintMargin(true);
        editor.session.setTabSize(2);
        editor.session.setUseSoftTabs(true);
        editor.session.setMode('ace/mode/ruby_sketchup');
        editor.session.setWrapLimitRange(null, null);
        editor.renderer.setPrintMarginColumn(80);
        editor.setOption('maxLines', 1000); // This autoresizes the editor.
        editor.setAutoScrollEditorIntoView(true); // Scrolls the editor into view on keyboard input.
        // Remove unwanted shortcuts
        editor.commands.removeCommand('goToNextError');     // Alt-E, Ctrl-E Shows an annoying bubble but no use here.
        editor.commands.removeCommand('goToPreviousError'); // Alt-Shift-E, Ctrl-Shift-E
        editor.commands.removeCommand('showSettingsMenu');  // Ctrl-, TODO: This is cool, but fails in IE duetounsuported JavaScript assEventListener. Check if there are polyfills.
        editor.commands.removeCommand('foldOther'); // This conflicts with keyboard layouts that use AltGr+0 for "}"

        // Function to submit input for evaluation.
        editor.submit = function (text) {
            // Increase the message count.
            message_id++;
            // Add the command to the output.
            var metadata = {type: 'input', language: Options.language, id: console_id + message_id};
            text = Extensions.trigger('onInput', text, metadata);
            output.add(text, metadata);
            // No need to eval empty commands.
            if (text && !/^\s*$/.test(text)) {
                // Send the command to ruby:
                if (Options.language === 'ruby') {
                    Bridge.call('eval', text, metadata);
                    // TODO: use promise here? and expose promise to extensions?
                }
                // Or language is JavaScript and we eval it here:
                else {
                    try {
                        var result = JSON.stringify(globalEval(text));
                        var metadata = {type: 'result', language: 'javascript', time: (new Date), source: metadata.id};
                        result = Extensions.trigger('onResult', result, metadata);
                        output.add(result, metadata);
                    } catch (e) {
                        /* This is already caught by `window.onerror` with complete metadata while here `e` has for some reason no properties. */
                        //AE.Console.error(e, {type: "result", language: "javascript", time: (new Date), source: metadata.id });
                    }
                }
            }
        };

        // Keyhandler to submit code for evaluation if Enter is pressed.
        editor.commands.addCommand({
            name: 'Evaluate code',
            bindKey: 'enter',
            exec: function (editor) {
                // Get the input.
                var command = editor.session.getValue();
                // Clear the input field.
                editor.session.setValue('');
                // Submit it.
                editor.submit(command);
                document.getElementById('input').scrollIntoView();
            },
            readOnly: true // false if this command should not apply in readOnly mode
        });

        // Keyhandler to override up/down navigation.
        editor.commands.addCommand({
            name: AE.Translate.get('Go one line up or back in the history.'),
            bindKey: 'up',
            exec: function (editor) {
                // If the cursor is in the first row.
                if (editor.getCursorPosition().row === 0) {
                    Extensions.trigger('onArrowUp', editor);
                } else {
                    editor.navigateUp();
                }
            }
        });

        // Keyhandler to override up/down navigation.
        editor.commands.addCommand({
            name: AE.Translate.get('Go one line down or forward in the history.'),
            bindKey: 'down',
            exec: function (editor) {
                // If the cursor is in the last row.
                if (editor.getCursorPosition().row + 1 === editor.session.getLength()) {
                    Extensions.trigger('onArrowDown', editor);
                } else {
                    editor.navigateDown();
                }
            }
        });

        /* OUTPUT FIELD */

        output = self.output = new Output(AE.$('#output'));

        AE.$('#output').className = AE.$('#input').className;
        AE.$('#content').className = 'ace-tm';
        // Since the editor's gutter would be missing from the output, we imitate it.
        // TODO: alternative: use editor as read-only for output.
        AE.$('#fake_gutter').className = 'ace_gutter';

        /* TOOLBAR BUTTONS */

        // Clear
        AE.Events.bind(AE.$('#button_clear'), 'click', function () {
            output.clear();
            editor.focus();
        });

        // Binding
        binding_element = AE.$('#button_binding');
        AE.Events.bind(binding_element, 'change', function () {
            var _this = this;
            var value = _this.value;
            // Invalid input
            if (!/^(\$|@@?)?[^\!\"\'\`\@\$\%\|\&\/\(\)\[\]\{\}\,\;\?\<\>\=\+\-\*\/\#\~\\]+$/.test(value)) {
                _this.value = 'global';
                value = 'global';
            }
            // Adjust the width.
            _this.style.width = (value.length / 1.5) + 'em'
            Bridge.call('set_binding', value, function (binding) {
                _this.value = binding;
                // Adjust the width.
                _this.style.width = (binding.length / 1.5) + 'em';
            });
        });

        // Verbosity
        verbosity_element = AE.$('[name=verbosity]')[0];
        AE.Events.bind(verbosity_element, 'change', function () {
            if (!/^(true|false|null)$/.test(this.value)) {
                return;
            }
            Options.verbose = (/true/.test(this.value)) ? true : (/false/.test(this.value)) ? false : null;
            Bridge.call('set_verbose', Options.verbose);
        });

        // Wrap lines
        wrap_lines_element = AE.$('[name=wrap_lines]')[0];
        AE.Events.bind(wrap_lines_element, 'change', function () {
            Options.wrap_lines = this.checked;
            Bridge.call('update_options', {wrap_lines: Options.wrap_lines});
            this.update();
        });
        wrap_lines_element.update = function () {
            if (Options.wrap_lines) {
                AE.Style.addClass(AE.$('#content'), 'wrap_lines');
            } else {
                AE.Style.removeClass(AE.$('#content'), 'wrap_lines');
            }
            editor.session.setUseWrapMode(Options.wrap_lines);
        };

        // Show time
        show_time_element = AE.$('[name=show_time]')[0];
        AE.Events.bind(show_time_element, 'change', function () {
            Options.show_time = this.checked;
            Bridge.call('update_options', {show_time: Options.show_time});
            this.update();
        });
        show_time_element.update = function () {
            AE.Style.setRule('#output .message .time', {
                display: (Options.show_time ? 'block' : 'none')
            });
        };

        // Initialize the menus.
        Menus.initialize();

        // Focus the editor.
        AE.Events.bind(AE.$('#output'), 'keydown', function (event) {
            if (!event.ctrlKey) {
                editor.focus();
            }
        });
        AE.Events.bind(AE.$('#content'), 'click', function (event) {
            if (event.target == this) {
                editor.focus();
            }
        });
        window.setTimeout(function () {
            editor.focus();
        }, 100);

        Bridge.call('get_options', setOptions);
    };

    /**
     * Initialize the UI (2) and set the options.
     * @param {object=} options
     */
    var setOptions = function (options) {
        // Load the options.
        if (!options) options = {};
        for (var o in options) {
            Options[o] = options[o];
        }
        if (Options.debug) AE.debug = Options.debug;

        // Set the console id that was assigned by the Ruby side.
        if (options.id) console_id += options.id + ":";

        // Load defaults.
        AE.Form.fill(Options);

        // Editor options
        try {
            editor.setTheme(Options.theme);
        } catch (e) {
        }

        editor.session.setUseWrapMode(Options.wrap_lines);

        /* TOOLBAR BUTTONS */
        binding_element.value = Options.binding;
        verbosity_element.value = Options.verbose;
        wrap_lines_element.value = Options.wrap_lines;
        // TODO: Why does this option initially not have an effect without timeout?
        window.setTimeout(wrap_lines_element.update, 100);
        show_time_element.update();

        // Hook for loading.
        Extensions.trigger('onLoad', Options);
    };


    /**
     * Add code-highlighting to a string.
     * @note This function leverages ace's highlight capabilities outside of the editor.
     *   Here we turn insible editing characters off so that they won't pollute the
     *   produced html if someone wants to select & copy text.
     *   The used language is the mode currently set in the ace.editor.session.
     * @param {string} string
     * @returns {string} - A string of html code with css classes for code-highlighting.
     */
    var highlight = self.highlight = function (string) {
        if (typeof string !== 'string' || string === '') {
            return '';
        }
        var orig_showInvisibles = editor.renderer.getShowInvisibles();
        editor.renderer.setShowInvisibles(false);
        var html = [];
        var strings = string.split(/\r?\n/);
        for (var i = 0; i < strings.length; i++) {
            if (strings[i] === "") {
                html.push('<br/>');
                continue;
            } // TODO: Should this be "\n" or "<br/>"?
            var data = editor.session.getMode().getTokenizer().getLineTokens(strings[i], 'start');
            editor.renderer.$textLayer.$renderSimpleLine(html, data.tokens);
            if (i + 1 < strings.length) {
                html.push('<br/>');
            } // TODO: Should this be "\n" or "<br/>"?
        }
        editor.renderer.setShowInvisibles(orig_showInvisibles);
        return html.join("");
    };


    /**
     * Get a list of continuous tokens preceding the given position in the editor.
     * The token list includes – if possible – all tokens needed for a valid object/class/module or chained methods.
     * @param {ace.session} session
     * @param {{row: number, column: number}}} pos
     * @returns {Array<string>} - An array of string.
     */
    var getCurrentTokenList = self.getCurrentTokenList = function (session, pos) {
        var TokenIterator = ace.require('ace/token_iterator').TokenIterator;
        var tokenIterator = new TokenIterator(session, pos.row, pos.column);
        var tokens = [];
        var currentToken = tokenIterator.getCurrentToken();
        if (currentToken == null) return tokens;
        tokens.unshift(currentToken.value);
        // Walk from the caret position backwards and collect tokens. Skip everything within brackets.
        var space = /^\s+$/,
            bracketOpen = /^[\(\[\{]$/,
            bracketClose = /^[\)\]\}]$/,
            bracketStack = [],
            bracketMatching = {'(': ')', '[': ']', '{': '}'},
            indexAccessor = /^[\[\]]$/;
        while (true) {
            currentToken = tokenIterator.stepBackward();
            if (currentToken == null) break;
            var token = currentToken.value;
            // Since we walk backwards, closing brackets are added to the stack.
            if (bracketClose.test(token)) {
                bracketStack.push(token);
                // And opening brackets that match the top stack element, remove it from the stack.
            } else if (bracketOpen.test(token)) {
                var last = bracketStack[bracketStack.length - 1];
                if (last == bracketMatching[token]) {
                    bracketStack.pop();
                    if (indexAccessor.test(token) && bracketStack.length == 0) {
                        token = '[]';
                        if (tokens[0] == '=') {
                            tokens[0] = token + '=';
                        } else {
                            tokens.unshift(token);
                        }
                    }
                } else {
                    break;
                }
            } else if (space.test(token)) {
                break;
            } else if (bracketStack.length == 0) {
                // TODO: add [] methods? Does it handle []=, \w= ?
                switch (tokens[0]) {
                    case '?.':
                        tokens[0] = '.';
                        tokens.unshift(token + '?');
                        break;
                    case '?':
                        tokens[0] = token + '?';
                        break;
                    case '!.':
                        tokens[0] = '.';
                        tokens.unshift(token + '!');
                        break;
                    case '!':
                        tokens[0] = token + '!';
                        break;
                    case '=':
                        tokens[0] = token + '=';
                        break;
                    default:
                        // Words outside of brackets. We want to collect those.
                        tokens.unshift(token);
                }
            }
        }
        return tokens;
    };


    /**
     * The Output
     * @class
     * @param {HTMLDivElement} elem
     * This renders the html of an output element.
     */
    var Output = self.Output = function (elem) {
        var element = elem,
            createNewRow = true,
            previousEntry = null;

        /**
         * Clears the output.
         */
        this.clear = function () {
            element.innerHTML = "";
        };

        /**
         * Add an item to the output.
         * @param {string} text
         * @param {object=} metadata
         */
        this.add = function (text, metadata) {
            if (typeof text !== 'string') {
                text = String(text);
            }
            if (!metadata) {
                metadata = {};
            }
            if (!metadata.type) {
                metadata.type = 'other';
            }
            metadata.language = metadata.language || Options.language;
            // Combine identical messages.
            if (text !== "\n" && /puts|print|error/.test(metadata.type) &&
                previousEntry && previousEntry.counter &&
                previousEntry.text && text === previousEntry.text && createNewRow) {
                return previousEntry.counter.increase();
            }
            // Unfortunately SketchUp's stdout and stderr have only one `write` method
            // that prints inline text. To produce new lines, it sends a single line break
            // afterwards. In that case we absorb the line break and let the next message
            // start in a new line.
            if (text === "\n" && /print|error/.test(metadata.type)) {
                createNewRow = true;
                return;
            }
            if (/input|result|error/.test(metadata.type)) {
                createNewRow = true;
            }
            // Attach to the previous item.
            if (createNewRow === false && previousEntry) {
                attach(text);
            }
            // Or create a new item and a new row.
            else {
                newRow(text, metadata);
            }
            // Print messages are always attached to the previous entry.
            createNewRow = !(/print/.test(metadata.type));
        };

        /**
         * Insert text to the previous entry.
         * @param {string} text
         * @private
         */
        var attach = function (text) {
            /*var span = document.createElement("code"); // TODO: remove
             span.innerHTML = highlight(text);
             previousEntry.appendChild(span);*/
            previousEntry.appendChild(document.createTextNode(text));
            // Update the attribute.
            previousEntry.text += text;
        };

        /**
         * Creates a new entry.
         * @param {string} text
         * @param {object=} metadata
         * @private
         */
        var newRow = function (text, metadata) {
            if (typeof text !== 'string') {
                return;
            }
            var div = document.createElement('div');
            div.className = metadata.type + ' message';
            div.className += ' ace_scroller ace_text-layer'; // Tweaks for ace.

            // Add gutter on the left side to continue the editor's gutter and for message channel indicators.
            var gutter = document.createElement('div');
            gutter.className = 'gutter';
            gutter.className += ' ace-chrome ace_gutter'; // Tweaks for ace.
            div.appendChild(gutter);

            // Hook for raw text.
            text = Extensions.trigger('onBeforeCodeAdded', text, metadata);

            // Add the code.
            if (/input|result/.test(metadata.type)) {
                var code = document.createElement('code');
                code.className = 'content';
                previousEntry = code;
                code.text = text; // Save original text as attribute.
                div.text = text;  // Save original text as attribute.
                var xml_text = highlight(text);
                // Hook for highlighted text.
                xml_text = Extensions.trigger('onBeforeHighlightedCodeAdded', xml_text, metadata);
                code.innerHTML = xml_text;
                div.appendChild(code);

                // Add Error details.
            } else if (/error|warn/.test(metadata.type)) {
                var panel = document.createElement('div');
                panel.className = 'content ui-widget';
                var header = document.createElement('div');
                header.className = 'ui-widget-header';
                header.appendChild(document.createTextNode(text));
                panel.appendChild(header);
                // Collapse long backtrace.
                if (metadata.backtrace) {
                    AE.Style.addClass(panel, 'collapsible-panel');
                    var content = document.createElement('div');
                    content.className = 'ui-widget-content backtrace';
                    for (var i = 0; i < metadata.backtrace.length; i++) {
                        var trace = document.createElement('div');
                        content.appendChild(trace);
                        if (metadata.backtrace_short) {
                            trace.title = metadata.backtrace[i].replace(/\:\d+(?:\:.+)?$/, '');
                            trace.appendChild(document.createTextNode(metadata.backtrace_short[i]));
                        } else {
                            trace.appendChild(document.createTextNode(metadata.backtrace[i]));
                        }
                    }
                    panel.appendChild(content);
                    AE.Style.hide(content);
                    AE.Style.addClass(panel, 'collapsed');
                    var collapsed = true;
                    AE.Events.bind(header, 'click', function () {
                        if (collapsed) {
                            AE.Style.show(content);
                            AE.Style.removeClass(panel, 'collapsed');
                        } else {
                            AE.Style.hide(content);
                            AE.Style.addClass(panel, 'collapsed');
                        }
                        collapsed = !collapsed;
                    });
                }
                previousEntry = div;
                div.text = text; // Save original text as attribute.
                div.appendChild(panel);

            } else { // if (/puts|print/.test(metadata.type))
                var code = document.createElement('code');
                code.className = 'content';
                // previousEntry = code; // TODO
                previousEntry = div;
                div.text = text; // Save original text as attribute.
                text1 = text.replace(/\</g, '&lt;').replace(/\>/g, '&gt;');
                text2 = Extensions.trigger('onBeforeHighlightedCodeAdded', text1, metadata);
                if (text2 == text1) {
                    code.appendChild(document.createTextNode(text));
                } else {
                    code.innerHTML = text2;
                }
                div.appendChild(code);
            }

            // Add counter to combine repeated entries.
            if (/puts|print|error|warn/.test(metadata.type)) { // TODO ////////////////////////////
                div.counter = document.createElement('div');
                div.counter.className = 'counter';
                div.appendChild(div.counter);
                div.counter.style.display = 'none';
                div.counter.value = 1;
                div.counter.increase = function () {
                    this.style.display = 'block';
                    this.value += 1;
                    div.counter.innerHTML = this.value;
                };
            }

            // Add time stamp.
            // Metadata contains time in seconds, and JavaScript uses milliseconds.
            var d = (metadata.time instanceof Date) ? metadata.time : (typeof metadata.time === 'number') ? new Date(metadata.time * 1000) : new Date;
            var time = String(d.getHours()).rjust(2, '0') + ':' +
                String(d.getMinutes()).rjust(2, '0') + ':' +
                String(d.getSeconds()).rjust(2, '0') + '.' +
                String(d.getMilliseconds()).rjust(3, '0');
            var timestamp = document.createElement('div');
            timestamp.className = 'time';
            timestamp.innerHTML = time;
            div.appendChild(timestamp);
            element.appendChild(div);

            // Hook for div added to output.
            Extensions.trigger('onCodeAdded', div, text, metadata);
        };
    }; // end @class Output


    /**
     * Manager for the menus.
     * @module
     */
    var Menus = self.Menus = function (self) {
        // Initialize the menus.
        var menus = {};

        /**
         * Initializes the menus.
         * @method
         */
        self.initialize = function () {
            var button_menus = AE.$('.button-menu');
            var menu_wrappers = [];
            for (var i = 0; i < button_menus.length; i++) {
                (function () {
                    var button = AE.$('.button', button_menus[i])[0];
                    var menu_wrapper = AE.$('.menu-wrapper', button_menus[i])[0];
                    var menu_content = AE.$('.menu', menu_wrapper)[0];
                    menu_wrappers.push(menu_wrapper);
                    menus[menu_content.getAttribute('name')] = menu_content;
                    button.pressed = false;
                    var activated = false;
                    var pressed = false;
                    // Method to show a menu.
                    menu_wrapper.show = function () {
                        AE.Style.show(menu_wrapper);
                        activated = true;
                    };
                    // Method to hide a menu.
                    menu_wrapper.hide = function () {
                        AE.Style.hide(menu_wrapper);
                        activated = false;
                    };
                    // Method to show a menu and hide all others.
                    menu_wrapper.activate = function (event) {
                        var a = !activated;
                        for (var i = 0; i < menu_wrappers.length; i++) {
                            menu_wrappers[i].hide();
                        }
                        if (a) {
                            menu_wrapper.show(menu_wrapper);
                        }
                        activated = a;
                        if (event) {
                            event.stopPropagation();
                        }
                    };
                    AE.Events.bind(button, 'click', menu_wrapper.activate);
                    // Prevent clicks in the menu from bubbling outside.
                    AE.Events.bind(menu_wrapper, 'click', function (event) {
                        event.stopPropagation();
                    });
                    // Method to add a new item to the menu.
                    menu_content.addItem = function (string_or_element, fn) {
                        var li = document.createElement('li');
                        if (typeof string_or_element === 'string') {
                            li.innerHTML = string_or_element;
                        } else {
                            li.appendChild(string_or_element)
                        }
                        menu_content.appendChild(li);
                        if (typeof fn === 'function') {
                            AE.Events.bind(li, 'click', fn);
                        }
                    };
                    // Method to remove an item from the menu.
                    menu_content.removeItem = function (element) {
                        menu_content.removeChild(element.parentNode);
                    }
                })();
            }
            // A click outside the menu should close it.
            AE.Events.bind(document.body, 'click', function () {
                for (var i = 0; i < menu_wrappers.length; i++) {
                    menu_wrappers[i].hide();
                }
            });
        };

        /**
         * Method to get a menu element.
         * @method
         * @param {string} name
         */
        self.getMenu = function (name) {
            return menus[name];
        };

        return self;
    }(self.Menus || {}); // end module Menus


    /**
     * Extensions
     * This module allows other Console functions to provide hooks in which extensions can add/modify functionality.
     * @module
     */
    var Extensions = self.Extensions = function (self) {
        var extensions = [];

        /**
         * Registers a new extension.
         * @param {object} extension - name: {string}, description: {string}, enabled: {boolean}, content: {function(object)}
         */
        self.register = function (extension) {
            if (extension.enabled && typeof extension.content == 'function') {
                extensions.push(extension);
                self[extension.name] = {};
                extension.content(self[extension.name]);
            }
        };


        /**
         * Triggers an event on all extensions that implement event handlers.
         * @param {string} event_name
         * @param {object...} data - any amount of arguments specific to the event.
         * @returns {object} - A (potentially modified) copy of the first argument.
         * @note: In JavaScript, strings are immutable. Because of that, modifications
         *  to strings create a new string and don't modify the receiver like in Ruby.
         *  So we need a mechanism to return a changed string. For simplicity we
         *  do this only for the first argument.
         *  When triggering an event and the main argument is a string that is
         *  allowed to be modified, then we need to assign the return value to the same variable:
         *  string = Extensions.trigger(event, string)
         */
        self.trigger = function (event_name, data) {
            var args = Array.prototype.slice.call(arguments).slice(1);
            for (var i = 0; i < extensions.length; i++) {
                var extension = extensions[i];
                if (typeof self[extension.name][event_name] === 'function') {
                    try {
                        var result = self[extension.name][event_name].apply(extension.content, args);
                        // Change the main (first) argument if a modified object is returned (ignore if undefined).
                        if (result !== args[0] && typeof result === typeof args[0]) {
                            args[0] = result;
                        }
                    } catch (e) {
                        e.name += ' in AE.Console.Extensions when triggering \'' + event_name + '\' on \'' + extensions[i].name + '\'';
                        AE.Console.javaScriptError(e);
                    }
                }
            }
            return args[0];
        };

        return self;
    }(self.Extensions || {}); // end @module Extensions

    return self;
}(AE.Console || {}); // end @module Console


// Catch errors in the WebDialog and send them to the console.
// There are some errors by the ACE editor (when double-clicking or selection
// that goes outside the editor) that would be silent in a normal Internet Explorer
// but cause popups in SketchUp.
window.onerror = function(message, url, lineNumber, column, errorObject) {
  //var error = new Error(errorMessage, url, lineNumber); // TODO: different between Firefox and IE, IE takes only fileName argument
  var error = errorObject || new Error();
  error.name = 'Error';
  error.message = message;
  error.fileName = url;
  error.lineNumber = lineNumber;
  AE.Console.javaScriptError(error);
  return true;
};


// Adding methods to the String class


/**
 * Repeat a string a given number of times.
 * @param {number} num - an integer
 * @returns {string} - the modified string
 */
if (typeof(String.prototype.repeat) === 'undefined') {
    String.prototype.repeat = function (num) {
        for (var i = 0, buf = ""; i < num; i++) {
            buf += this;
        }
        return buf;
    }
}


/**
 * Fill up a string to a new width so that the original string is aligned at the right.
 * @param {number} width - an integer
 * @param {string=} padding - a single character to be used as padding, otherwise a space.
 * @returns {string} - the modified string
 */
if (typeof(String.prototype.rjust) === 'undefined') {
    String.prototype.rjust = function (width, padding) {
        padding = padding || " ";
        padding = padding.substr(0, 1);
        if (this.length < width) {
            return padding.repeat(width - this.length) + this;
        } else {
            return this;
        }
    }
}


/**
 * Evalutes JavaScript code in a global context and returns the return value.
 * @method
 * @note obtained from: http://whattheheadsaid.com/2011/08/global-eval-with-a-result-in-internet-explorer
 */
var globalEval = (function () {
    var isIndirectEvalGlobal = (function (original, Object) {
        try {
            // Does `Object` resolve to a local variable, or to a global, built-in `Object`,
            // reference to which we passed as a first argument?
            return window.eval('Object') === original;
        }
        catch (error) {
            // if indirect eval errors out (as allowed per ES3), then just bail out with `false`
            return false;
        }
    })(Object, 123);

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
