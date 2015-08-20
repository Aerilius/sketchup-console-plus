/* TODO: document: Patches to ext-modelist.js, ext-settings_menu.js to reduce modes to smaller selection.
- extensions more like module pattern: imports, exports
- merge ui_bootstrap with api.js
- bootstrap collapsible for errors
- loading of settings and setting ui (✓)
- decide which settings are for each editor/console or for both
- scrollbars
- auto-resize
- refactor output
- docbrowser docprovider autocompleter
- line numbers in output gutter
*/
var AE = window.AE || {};

AE.Console = AE.Console || {};

/*AE.Console.UI = */(function() { // ace, $, Bridge, document, Menu, AE.Console, Settings

    var console, output, editor, consoleMenu, editorMenu,
        settings = new Settings();

    function initialize() {
        var consoleAceEditor, editorAceEditor;
        // Load translations and translate the html document.
        Bridge.call('translate');

        initializeSettings();

        // Console Controller
        consoleAceEditor = ace.edit('consoleInput');
        initializeConsoleUI(consoleAceEditor);
        configureAce(consoleAceEditor);
        configureOutput();

        // Editor Controller
        editorAceEditor = ace.edit('editorInput');
        initializeEditorUI(editorAceEditor);
        configureAce(editorAceEditor);

        output = new AE.Console.Output($('#consoleOutput')[0], settings);
        console = new AE.Console.Console(consoleAceEditor, output, settings);
        editor = new AE.Console.Editor(editorAceEditor, settings);

        // The console is first visible, so focus the console ace editor.
        (settings.get('console_active')) ? switchToConsole() : switchToEditor();

        // Load settings from SketchUp
        Bridge.call('get_settings', settings.load);

        // Initialize the API.
        var extensionAccess = {
            settings: settings,
            console: console,
            output: output,
            editor: editor,
            consoleMenu: consoleMenu, // Or move this into console?
            editorMenu: editorMenu    // Or move this into editor?
            // Also expose aceEditor in console and editor
        };
        AE.Console.initialize(extensionAccess);
    }


    function initializeSettings() {
        // Create placeholders for required properties in settings. // TODO: remove
        settings.load({
            "fontSize": 12,
            "tabSize": 2,
            "useSoftTabs": true,
            "useWrapMode": true,
            "consoleMode": "ace/mode/ruby_sketchup",
            "editMode": "ace/mode/ruby_sketchup",
            "executionContext": "global",
            "theme": "ace/theme/chrome",
            "auto_reload": ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m"]
        });
    }


    function initializeConsoleUI (aceEditor) {
        $('#buttonConsoleSwitchToEditor').on('click', switchToEditor);

        $('#buttonConsoleClear').on('click', function () {
            console.clearOutput();
        });

        $('#buttonConsoleHelp').on('click', function () {
            Bridge.call('open_help', console.getCurrentTokens());
        });

        $('#buttonConsoleSelect').on('click', function () {
            var selectionRange = aceEditor.getSelectionRange();
            var selectedText   = aceEditor.session.getTextRange(selectionRange);
            Bridge.get('select_entity', selectedText).then(function (name) {
                aceEditor.getSession().getDocument().replace(selectionRange, name);
                window.focus();
                aceEditor.focus();
            });
        });

        // Console Menu
        consoleMenu = new Menu($('#menuConsole')[0]);
        settings.addListener('load', function () {

            consoleMenu.addProperty(settings.getProperty('fontSize'));

            consoleMenu.addProperty(settings.getProperty('tabSize'));

            consoleMenu.addProperty(settings.getProperty('useSoftTabs'));

            consoleMenu.addProperty(settings.getProperty('useWrapMode'));

            consoleMenu.addProperty(settings.getProperty('executionContext'));

            consoleMenu.addAlternativesProperty(settings.getProperty('consoleMode'), ['ace/mode/ruby_sketchup', 'ace/mode/javascript'], ['Ruby', 'JavaScript']);

            settings.getProperty('consoleMode').bindAction('change', function (value) {
                aceEditor.session.setMode(value);
            });

            addThemeList(consoleMenu);

            // Submenu for auto reload feature.
            var auto_reload_menu = new Menu('<ul class="dropdown-menu menu" style="top: 0; left: -25em; width: 25em">');
            var auto_reload_files = settings.get('auto_reload') || [];
            auto_reload_menu.addItem($('<b>')
                .text(AE.Translate.get('Click to remove files from auto-loading')));
            $.each(auto_reload_files, function(i, filename){
                auto_reload_menu.addItem(filename, function(event){
                    event.stopPropagation();
                    auto_reload_files.splice(auto_reload_files.indexOf(filename), 1);
                    settings.set('auto_reload', auto_reload_files);
                    auto_reload_menu.removeItem(filename);
                });
            });
            consoleMenu.addSubmenu(auto_reload_menu, 'auto_reload');
        });
    }


    function initializeEditorUI (aceEditor) {
        $('#buttonEditorSwitchToConsole').on('click', switchToConsole);

        $('#buttonEditorOpen').popover({
            placement: 'bottom',
            container: 'body',
            html: true,
            trigger: 'manual',
            content: createPopoverOpen
        }).on('click', function () {
            $(this).popover('toggle');
        });

        $('#buttonEditorRun').on('click', function () {
            Bridge.get('eval', editor.getContent()).then(function () {
                // TODO: Notification
            }, function (error) {
                // TODO: Notification
            });
        });

        $('#buttonEditorHelp').on('click', function () {
            Bridge.call('open_help', editor.getCurrentTokens());
        });

        $('#buttonEditorSave').on('click', function () {
            editor.save();
        });

        // Editor menu
        editorMenu = new Menu($('#menuEditor')[0]);
        settings.addListener('load', function () {

            editorMenu.addItem('New', function(){
                editor.newDocument().then(function(filename) {
                    $('#labelEditorFilename').text(filename);
                });
            });

            editorMenu.addItem('Save as…', function(){
                editor.saveAs().then(function(filename) {
                    $('#labelEditorFilename').text(filename);
                });
            });

            editorMenu.addSeparator();

            editorMenu.addItem('Find…', function(){
                aceEditor.commands.exec("find", aceEditor);
            });

            editorMenu.addItem('Find and Replace…', function(){
                aceEditor.commands.exec("replace", aceEditor);
            });

            editorMenu.addItem('Go to line…', function(){
                aceEditor.commands.exec("gotoline", aceEditor);
            });

            editorMenu.addSeparator();

            editorMenu.addProperty(settings.getProperty('fontSize'));

            editorMenu.addProperty(settings.getProperty('tabSize'));

            editorMenu.addProperty(settings.getProperty('useSoftTabs'));

            editorMenu.addProperty(settings.getProperty('useWrapMode'));

            // TODO: decide which settings are for each editor/console or for both

            ace.config.loadModule('ace/ext/modelist', function (modelist) {
                var modeNames = [], modeKeys = [];
                $.each(modelist.modesByName, function(index, mode) {
                    modeNames.push(mode.caption);
                    modeKeys.push(mode.mode);
                });
                editorMenu.addAlternativesProperty(settings.getProperty('editMode'), modeKeys, modeNames);
            });
            settings.getProperty('editMode').bindAction('change', function (value) {
                aceEditor.session.setMode(value); // TODO: not working
            });

            addThemeList(editorMenu);
        });
    }


    function addThemeList (menu) {
        ace.config.loadModule('ace/ext/themelist', function (themelist) {
            var themeNames = [], themeKeys = [];
            $.each(themelist.themes, function(index, theme) {
                if (!theme.isDark) {
                    themeNames.push(theme.caption);
                    themeKeys.push(theme.theme);
                }
            });
            $.each(themelist.themes, function(index, theme) {
                if (theme.isDark) {
                    themeNames.push(theme.caption);
                    themeKeys.push(theme.theme);
                }
            });
            menu.addAlternativesProperty(settings.getProperty('theme'), themeKeys, themeNames);
        });
    }


    function switchToEditor () {
        /*$('#console').animate({left: '-100%'}, function () { $(this).hide(); });
        $('#editor').show().animate({left: 0});
        editor.focus();*/
        $('#consoleToolbar').hide();
        $('#editorToolbar').show();
        $('#consoleContentWrapper').animate({left: '-100%'});
        $('#editorContentWrapper').animate({left: 0});
        editor.focus();
    }


    function switchToConsole () {
        /*$('#console').show().animate({left: 0});
        $('#editor').animate({left: '100%'}, function () { $(this).hide(); });
        console.focus();*/
        $('#buttonEditorOpen').popover('hide');
        $('#consoleToolbar').show();
        $('#editorToolbar').hide();
        $('#consoleContentWrapper').animate({left: 0});
        $('#editorContentWrapper').animate({left: '100%'});
        console.focus();
    }


    function createPopoverOpen () {
        var $attached = $(this),
            $search   = $('<input style="width:100%" type="search">'),
            $recentList = $('<ul>').css({'height': '10em', 'overflow': 'hidden', 'overflow-y': 'scroll', 'text-overflow': 'ellipsis'}),
            $searchList = $('<ul>').css({'height': '10em', 'overflow': 'hidden', 'overflow-y': 'scroll', 'text-overflow': 'ellipsis'}),
            $buttonOpen = $('<button style="width:100%">').text(AE.Translate.get('More files…'));
        // Add event handlers to hide the popover again on esc or click outside.
        $attached.on('shown.bs.popover', function (event) {
            var popover = $(this);
            var hide = function () {
                popover.popover('hide');
            };
            var escHide = function(event) {
                if (event.which == 27) hide(); // esc
            };
            popover.on('hide.bs.popover', function () {
                $(document).off('click', hide);
                $(document).off('keydown', escHide);
            });
            $(document).one('click', hide);
            $(document).on('keydown', escHide);
        });
        // Load by default a list of recently edited files.
        Bridge.get('get_recently_edited').then(function (filepaths) {
            $.each(filepaths, function (index, filepath) {
                $('<li>').text(filepath).on('click', function () {
                    editor.open(filepath).then(function(filename) {
                        $('#labelEditorFilename').text(filename);
                    });
                    $attached.popover('hide');
                }).appendTo($recentList);
            });
        });
        // Search field: On key input, load matching file paths.
        $search.on('keyup', function () {
            var searchTerm = $search.val();
            if (searchTerm.length == 0) {
                $searchList.empty();
                $searchList.hide();
                $recentList.show();
            } else {
                Bridge.get('search_files', searchTerm).then(function (filepaths) {
                    $recentList.hide();
                    $searchList.show();
                    $searchList.empty();
                    $.each(filepaths, function (index, filepath) {
                        $('<li>').css({'white-space': 'pre', 'float': 'right'})// TODO: why this css?
                            .attr('title', filepath).text(filepath)
                            .on('click', function () {
                                editor.open(filepath).then(function (filename) {
                                    $('#labelEditorFilename').text(filename);
                                });
                                $attached.popover('hide');
                            }).appendTo($searchList);
                    });
                });
            }
        });
        // Open button: opens the traditional file selector.
        $buttonOpen.on('click', function () {
            Bridge.get('openpanel', AE.Translate.get('Open a text file to edit'))
            .then(function (filepath) {
                editor.open(filepath).then(function(filename) {
                    $('#labelEditorFilename').text(filename);
                });
                $attached.popover('hide');
            });
        });
        // Return a div element with all popover content.
        return $('<div>').append(
            $search,
            $searchList,
            $buttonOpen
        ).on('click', function (event) {
            event.stopPropagation();
        });
    }


    function configureAce (aceEditor) {
        // Hack to hide the scrollbar. // TODO: scrollbar should show up in editorEditor
        /*ace.require('ace/lib/dom').scrollbarWidth = function (document) {
            return 0;
        };*/
        // Add default settings.
        aceEditor.setDisplayIndentGuides(true);
        aceEditor.setHighlightActiveLine(true);
        aceEditor.setHighlightSelectedWord(true);
        aceEditor.setSelectionStyle('line');
        aceEditor.setShowInvisibles(true);
        aceEditor.renderer.setShowGutter(true);
        aceEditor.renderer.setShowPrintMargin(true);
        aceEditor.session.setWrapLimitRange(null, null);
        aceEditor.renderer.setPrintMarginColumn(80);
        //aceEditor.setOption('maxLines', 1000); // This autoresizes the editor.
        // TODO: fix height of editorEditor: should fill space but not exceed, should scroll
        aceEditor.setAutoScrollEditorIntoView(true); // Scrolls the editor into view on keyboard input.
        aceEditor.$blockScrolling = Infinity;

        // Remove unwanted shortcuts
        aceEditor.commands.removeCommand('goToNextError');     // Alt-E, Ctrl-E Shows an annoying bubble but no use here.
        aceEditor.commands.removeCommand('goToPreviousError'); // Alt-Shift-E, Ctrl-Shift-E
        aceEditor.commands.removeCommand('showSettingsMenu');  // Ctrl-, TODO: This is cool, but fails in IE due to unsupported JavaScript addEventListener. Check if there are polyfills.
        aceEditor.commands.removeCommand('foldOther'); // This conflicts with keyboard layouts that use AltGr+0 for "}"

        // When settings are loaded from Ruby, we will bind them to actions. // TODO: why on load and not before?
        settings.getProperty('fontSize').bindAction('change', function (value) {
            aceEditor.setFontSize(value);
            $('#consoleContent').css({'font-size': value + 'px'});
        });
        settings.getProperty('tabSize').bindAction('change', function (value) {
            aceEditor.session.setTabSize(value);
        });
        settings.getProperty('useSoftTabs').bindAction('change', function (value) {
            aceEditor.session.setUseSoftTabs(value); // TODO: not working
        });
        settings.getProperty('useWrapMode').bindAction('change', function (value) {
            aceEditor.session.setUseWrapMode(value); // TODO: test
        });
        settings.getProperty('theme').bindAction('change', function(value) {
            try {
                var regexp = /[^\/]+$/;
                var themeClassOld = 'ace-' + regexp.exec(aceEditor.getTheme())[0];
                aceEditor.setTheme(value, function(){ // asynchronous
                    // Assumption: css class name from theme name
                    var themeClassNew = 'ace-' + regexp.exec(value)[0];
                    // This must be synced when ace editor theme is changed, not by directly listening theme property.
                    $('#consoleContent').removeClass(themeClassOld).addClass(themeClassNew);
                });
            } catch (e) {}
        });
    }


    function configureOutput() {
        // TODO: or in output class initializer?
        $('#consoleOutput').addClass($('#consoleInput').attr('class'));
        // This allows child-element #consoleOutputFakeGutter to be themed like .ace-tm .ace_gutter.
        $('#consoleContent').addClass('ace-tm');
        // Since the editor's gutter would be missing from the output, we imitate it.
        $('#consoleOutputFakeGutter').addClass('ace_gutter');
        // If the console input is smaller than the clickable free space, redirect clicks to focus the console input.
        $("#consoleContent").on('click', function(event) {
            if (event.target == $(this)[0]) console.focus();
        });
    }


    // jQuery on document ready
    $(initialize);
})();


/**
 *
 * @class
 */
var Menu = function (element) {

    var $menuElement = $(element||'<ul>');
    var $menuItems = {};
    this.element = $menuElement[0];
    // Workaround: bootstrap dropdown-menu closes on click.
    /*$menuElement.on('click', function (event) {
        event.stopPropagation();
    });*/

    /**
     * Add an arbitrary item to the menu.
     * @overload
     *   @param item {HTMLElement, string, jQuery} - The html to add for this item.
     *   @param name {string}                      - A short identifier to access this item again.
     *   @param onClickedCallback {function}       - An optional callback when the item is clicked.
     * @overload
     *   @param item {HTMLElement, string, jQuery} - The html to add for this item.
     *   @param onClickedCallback {function}       - An optional callback when the item is clicked.
     * @returns {Menu}
     */
    this.addItem = function (item, name, onClickedCallback) {
        if (!(item && item.jquery || typeof item === 'string' || item instanceof HTMLElement)) { throw TypeError("addItem must be called with an HTML element or HTML string"); };
        if (typeof name === 'function') { onClickedCallback = name; name = item; }
        var $li;
        $li = $('<li>').append(item);
        $menuElement.append($li);
        $menuItems[name||item] = $li;
        if (typeof onClickedCallback === 'function') $li.on('click', onClickedCallback);
        return this; // TODO: Should the `add*` methods return the name (id)?
    };

    this.removeItem = function (id) {
        $menuItems[id] && $menuItems[id].remove();
        return this;
    };

    this.addSeparator = function () {
        $menuElement.append('<hr>');
        return this;
    };

    this.addSubmenu = function (menu, name, onClickedCallback) {
        if (!(menu && menu.constructor === this.constructor)) { throw TypeError("addSubmenu must be called with a Menu"); };
        if (typeof name === 'function') { onClickedCallback = name; name = menu; }
        var $li;
        $li = $('<li>').text(AE.Translate.get(name)).append(menu.element);
        $li.attr('data-toggle', 'dropdown').dropdown()
        .on('mouseover', function(event){
            $(menu.element).toggle(true);
        }).on('mouseout', function(event) {
            $(menu.element).toggle(false);
        });
        // Workaround: click on item that has submenu closes bootstrap parent menu.
        $li.off('click');
        $li.on('click', function (event) {
            event.stopPropagation();
        });
        $menuElement.append($li);
        $menuItems[name] = $li;
        
        return this;
    };

    this.addProperty = function (property) {
        var $input, $li,
            name = property.getName(),
            value = property.getValue();
        if (typeof value === 'number') {
            // Number input
            $input = $('<input type="number">').val(value);
        } else if (typeof value === 'string') {
            // Text input
            $input = $('<input type="text">').val(value);
        } else if (typeof value === 'boolean') {
            // Checkbox
            $input = $('<input type="checkbox">').attr('checked', value);
        } else {
            return; // unsupported property type
        }
        $input.attr('name', name);
        // Bind the property with the input.
        property.bindAction('change', function(newValue) {
            // This programmatical change of the input's value does not trigger the input's change event.
            $input.val(newValue);
        });
        $input.on('change', function () {
            if (typeof value === 'number') {
                property.setValue(Number($input.val()));
            } else {
                property.setValue($input.val());
            }
        });
        // Add a label and the input to the menu.
        $li = $('<li>').append(
            $('<label>').text(AE.Translate.get(name)).append($input)
        );
        $li.on('click', function (event) {
            event.stopPropagation();
        });
        $menuElement.append($li);
        $menuItems[name] = $li;
        return this;
    };

    this.addAlternativesProperty = function (property, alternatives, alternativesDisplayNames) {
        var $input, $li,
            name = property.getName(),
            value = property.getValue(); // TODO: reduncant
        if (!alternativesDisplayNames) alternativesDisplayNames = alternatives;
        // Create a select input.
        $input = $('<select>');
        for (var i = 0; i < alternatives.length; i++) {
            $input.append(
                $('<option>')
                    .val(alternatives[i])
                    .text(AE.Translate.get(alternativesDisplayNames[i]))
            );
        }
        // Apply the property's value as selected value.
        // $input.val(value); // TODO: reduncant
        $input.attr('name', name);
        // Bind the property with the input.
        property.bindAction('change', function(newValue) {
            // This programmatical change of the input's value does not trigger the input's change event.
            $input.val(newValue);
        });
        $input.on('change', function () {
            property.setValue($input.val());
        });
        // Add a label and the input to the menu.
        $li = $('<li>').append(
            $('<label>').text(AE.Translate.get(name)).append($input)
        );
        $li.on('click', function (event) {
            event.stopPropagation();
        });
        $menuElement.append($li);
        $menuItems[name] = $li;
        return this;
    };
};
