define(['ace/ace', 'jquery', 'bootstrap', 'bootstrap-notify', 'bootstrap-filterlist', './bridge', './translate', './settings', './menu', './console', './editor', './output', './enable_zoom'], function (ace, $, _, _, _, Bridge, Translate, Settings, Menu, Console, Editor, Output) {

    var console, output, editor, consoleMenu, editorMenu,
        settings = new Settings();

    function initialize () {
        var consoleAceEditor, editorAceEditor;
        // Notify the other side that HTML is loaded.
        Bridge.call('loaded');

        // Load translations and translate the html document.
        Bridge.call('translate');

        initializeSettings();

        // Output
        configureOutput();
        output = new Output($('#consoleOutput')[0], settings);

        // Console Controller
        consoleAceEditor = ace.edit('consoleInput');
        configureAce(consoleAceEditor);
        console = new Console(consoleAceEditor, output, settings);
        initializeConsoleUI(console, settings);

        // Editor Controller
        editorAceEditor = ace.edit('editorInput');
        editor = new Editor(editorAceEditor, settings);
        initializeEditorUI(editor, settings);
        configureAce(editorAceEditor);

        //switchToConsole(true); // default

        settings.getProperty('console_active').addListener('change', function (isActive) {
            if (isActive) {
                switchToConsole();
            } else {
                switchToEditor();
            }
        });

        // Load settings from SketchUp
        Bridge.call('get_settings', settings.load);
    }

    function initializeSettings () {
        // Create placeholders for required properties in settings.
        settings.load({
            'fontSize': 12,
            'tabSize': 2,
            'useSoftTabs': true,
            'useWrapMode': true,
            'editMode': 'ace/mode/ruby_sketchup',
            'theme': 'ace/theme/chrome'
        });
    }

    function initializeConsoleUI (console, settings) {
        // Toolbar buttons
        $('#buttonConsoleSwitchToEditor').attr('title', Translate.get('Editor'));
        $('#buttonConsoleSwitchToEditor').on('click', function () {
            settings.getProperty('console_active').setValue(false);
        });

        $('#buttonConsoleClear').attr('title', Translate.get('Clear')+' (Ctrl+L)');
        $('#buttonConsoleClear').on('click', function () {
            console.clearOutput();
        });

        // Console Menu
        consoleMenu = new Menu($('#menuConsole')[0]);

        consoleMenu.addProperty(settings.getProperty('fontSize'));

        consoleMenu.addProperty(settings.getProperty('tabSize'));

        consoleMenu.addProperty(settings.getProperty('useSoftTabs'));

        consoleMenu.addProperty(settings.getProperty('useWrapMode'));

        addThemeListToMenu(consoleMenu);
    }

    function initializeEditorUI (editor, settings) {
        // Toolbar buttons
        $('#buttonEditorSwitchToConsole').attr('title', Translate.get('Console'));
        $('#buttonEditorSwitchToConsole').on('click', function () {
            settings.getProperty('console_active').setValue(true);
        });

        $('#buttonEditorOpen').attr('title', Translate.get('Open'));
        $('#buttonEditorOpen').popover({
            placement: 'bottom',
            container: 'body',
            html: true,
            trigger: 'manual',
            content: createPopoverOpen
        }).on('click', function () {
            $(this).popover('toggle');
            $(this).data('bs.popover').$tip.find('input').focus();
        });

        $('#buttonEditorRun').attr('title', Translate.get('Run'));
        $('#buttonEditorRun').on('click', function () {
            if (settings.get('editMode') == 'ace/mode/ruby_sketchup') {
                var notify = $.notify(Translate.get('Running the code…'), {
                    type: 'info',
                    element: $('#editorContentWrapper'),
                    placement: { from: 'top', align: 'center' },
                    offset: { x: 0, y: 0 },
                    mouse_over: 'pause',
                    allow_dismiss: true
                });
                notify.$ele.removeClass('col-xs-11'); // Hack to disable responsiveness (notification stretching over full width in narrow dialogs).
                // Dispatch the code evaluation to allow the GUI to update (show the notification) 
                // in case code evaluation freezes the GUI.
                window.setTimeout(function() {
                    Bridge.get('eval', editor.getContent()).then(function (result, metadata) {
                        var successMessage = (result != 'nil') ? Translate.get('Code was run and returned: \n %0', $('<code>').text(result).html()) : Translate.get('Code was run successfully!');
                        notify.update({ message: successMessage, type: 'success', allow_dismiss: true, delay: 3000 });
                    }, function (errorMetadata) {
                        var errorMessage = Translate.get('Code failed with an error: \n %0', errorMetadata.message);
                        notify.update({ message: errorMessage, type: 'danger', allow_dismiss: true, delay: 3000 });
                    });
                }, 10);
            } else {
                $.notify(Translate.get('Only Ruby code can be run.') + ' \n' + 
                        Translate.get('If this is Ruby code, set the edit mode in the menu.'), {
                    type: 'warning',
                    element: $('#editorContentWrapper'),
                    placement: { from: 'top', align: 'center' },
                    offset: { x: 0, y: 0 },
                    allow_dismiss: true
                });
            }
        });

        $('#buttonEditorSave').attr('title', Translate.get('Save'));
        $('#buttonEditorSave').on('click', function () {
            editor.save();
        });

        // Editor title (filename of currently opened file)
        editor.addListener('opened', function(filepath) {
            if (!filepath || filepath == '') {
                $('#labelEditorFilename').text(Translate.get('Unsaved document'));
                $('#labelEditorFilepath').text('').hide();
            } else {
                $('#labelEditorFilename').text(getBasename(filepath));
                $('#labelEditorFilepath').text(getDirname(filepath)).show();
            }
        });
        editor.addListener('saved', function(filepath) {
            $('#labelEditorFilename').text(getBasename(filepath));
            $('#labelEditorFilepath').text(getDirname(filepath)).show();
        });

        // Editor menu
        editorMenu = new Menu($('#menuEditor')[0]);

        editorMenu.addItem('New', function(){
            editor.newDocument().then(function(filename) {
                editor.aceEditor.focus();
            });
        });

        editorMenu.addItem('Save as…', function(){
            editor.saveAs().then(function(filename) {
                editor.aceEditor.focus();
            });
        });

        editorMenu.addSeparator();

        editorMenu.addItem('Find…', function(){
            editor.aceEditor.commands.exec('find', editor.aceEditor);
        });

        editorMenu.addItem('Find and Replace…', function(){
            editor.aceEditor.commands.exec('replace', editor.aceEditor);
        });

        editorMenu.addItem('Go to line…', function(){
            editor.aceEditor.commands.exec('gotoline', editor.aceEditor);
            editor.aceEditor.focus();
        });

        editorMenu.addSeparator();

        editorMenu.addProperty(settings.getProperty('fontSize'));

        editorMenu.addProperty(settings.getProperty('tabSize'));

        editorMenu.addProperty(settings.getProperty('useSoftTabs'));

        editorMenu.addProperty(settings.getProperty('useWrapMode'));

        ace.config.loadModule('ace/ext/modelist', function (modelist) {
            /*var modeNames = [], modeKeys = [];
            $.each(modelist.modesByName, function(index, mode) {
                modeNames.push(mode.caption);
                modeKeys.push(mode.mode);
            });*/
            var modeNames = ['Ruby', 'BatchFile', 'C and C++', 'CSS', 'HTML', 'JavaScript', 'JSON', 'Markdown', 'Powershell', 'SH', 'SVG', 'Text', 'Typescript', 'XML', 'YAML'];
            var modeKeys = ['ace/mode/ruby_sketchup', 'ace/mode/batchfile', 'ace/mode/c_cpp', 'ace/mode/css', 'ace/mode/html', 'ace/mode/javascript', 'ace/mode/json', 'ace/mode/markdown', 'ace/mode/powershell', 'ace/mode/sh', 'ace/mode/svg', 'ace/mode/text', 'ace/mode/typescript', 'ace/mode/xml', 'ace/mode/yaml'];
            editorMenu.addAlternativesProperty(settings.getProperty('editMode'), modeKeys, modeNames);
        });
        settings.getProperty('editMode').bindAction('change', function (value) {
            editor.aceEditor.session.setMode(value);
        });

        addThemeListToMenu(editorMenu);

        editorMenu.addItem('Show shortcuts', function () {
            ace.config.loadModule("ace/ext/keybinding_menu", function(module) {
                module.init(editor.aceEditor);
                editor.aceEditor.showKeyboardShortcuts()
            })
        });
    }

    function addThemeListToMenu (menu) {
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

    function switchToEditor (immediate) {
        if ($('#editorToolbar').is(':visible')) immediate = true;
        $('#consoleToolbar').hide();
        $('#editorToolbar').show();
        if (immediate === true) {
          $('#consoleContentWrapper').css({left: '-100%'});
          $('#editorContentWrapper').css({left: 0});
        } else { // animate
          $('#consoleContentWrapper').animate({left: '-100%'});
          $('#editorContentWrapper').animate({left: 0});
        }
        editor.focus();
    }

    function switchToConsole (immediate) {
        if ($('#consoleToolbar').is(':visible')) immediate = true;
        $('#buttonEditorOpen').popover('hide');
        $('#consoleToolbar').show();
        $('#editorToolbar').hide();
        if (immediate === true) {
          $('#consoleContentWrapper').css({left: 0});
          $('#editorContentWrapper').css({left: '100%'});
        } else { // animate
          $('#consoleContentWrapper').animate({left: 0});
          $('#editorContentWrapper').animate({left: '100%'});
        }
        console.focus();
    }

    function createPopoverOpen () {
        var $attached = $(this),
            $search   = $('<input style="width:100%" type="search">'),
            $searchList = $('<ul>').css({'height': '10em', 'overflow': 'hidden', 'overflow-y': 'scroll', 'text-overflow': 'ellipsis'}),
            $buttonOpen = $('<button style="width:100%">').text(Translate.get('More files…'));
        // Add event handlers to hide the popover again on esc or click outside.
        $attached.on('shown.bs.popover', function (event) {
            var $popover = $(this);
            var hide = function () {
                $popover.popover('hide');
            };
            var escHide = function(event) {
                if (event.which == 27) hide(); // esc
            };
            $popover.on('hide.bs.popover', function () {
                $(document).off('click', hide);
                $(document).off('keydown', escHide);
            });
            $(document).one('click', hide);
            $(document).on('keydown', escHide);
        });
        
        // Load by default a list of recently edited files.
        var recentlyOpened = settings.getProperty('recently_opened_files', []);
        $search.filterlist({
            source: function (searchTerm, process) {
                Bridge.get('search_files', searchTerm).then(process);
            },
            defaultData: function () {
                return recentlyOpened.getValue();
            },
            menu: $searchList,
            renderer: function (filepath, searchTerm) {
                var dirname = getDirname(filepath);
                var basename = getBasename(filepath);
                dirname = dirname.replace();
                // Highlight the search term in the filepath
                if (searchTerm.length > 0) {
                    searchTerm = searchTerm.replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, '\\$&')
                    var regexp = new RegExp('(' + searchTerm + ')', 'ig');
                    function replacement ($1, match) {
                      return '<strong>' + match + '</strong>'
                    }
                    dirname = dirname.replace(regexp, replacement);
                    basename = basename.replace(regexp, replacement);
                }
                
                return $('<li>').append([
                    $('<span>').html(basename),
                    $('<br>'),
                    $('<span>').addClass('ellipsis-left').css({'opacity': 0.5, 'font-size': '80%', 'line-height': '1em'}).html(dirname),
                    $('<div>').css({clear: 'both'}) // clearfix for float of ellipsis-left
                ]);
            },
            updater: function (filepath) {
                editor.open(filepath);
                $attached.popover('hide');
            }
        });
        recentlyOpened.addListener('change', function (value) {
            $search.filterlist('reset');
        });

        // Open button: opens the traditional file selector.
        $buttonOpen.on('click', function () {
            Bridge.get('openpanel', Translate.get('Open a text file to edit'), editor.getCurrentFilePath())
            .then(function (filepath) {
                editor.open(filepath);
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
        aceEditor.setAutoScrollEditorIntoView(true); // Scrolls the editor into view on keyboard input.
        aceEditor.$blockScrolling = Infinity;

        // Remove unwanted shortcuts
        aceEditor.commands.removeCommand('goToNextError');     // Alt-E, Ctrl-E Shows an annoying bubble but no use here.
        aceEditor.commands.removeCommand('goToPreviousError'); // Alt-Shift-E, Ctrl-Shift-E
        aceEditor.commands.removeCommand('showSettingsMenu');  // Ctrl-, This is cool, but fails in IE due to unsupported JavaScript addEventListener. Check if there are polyfills.
        aceEditor.commands.removeCommand('foldOther');         // This conflicts with keyboard layouts that use AltGr+0 for "}"

        // When settings are loaded from Ruby, we will bind them to actions.
        settings.getProperty('fontSize').bindAction('change', function (value) {
            aceEditor.setFontSize(value);
            $('#consoleContent').css({'font-size': value + 'px'});
        });
        settings.getProperty('tabSize').bindAction('change', function (value) {
            aceEditor.session.setTabSize(value);
        });
        settings.getProperty('useSoftTabs').bindAction('change', function (value) {
            aceEditor.session.setUseSoftTabs(value);
        });
        settings.getProperty('useWrapMode').bindAction('change', function (value) {
            aceEditor.session.setUseWrapMode(value);
        });
        settings.getProperty('theme').bindAction('change', function(value) {
            try {
                // The theme name is not the same as the CSS class.
                var themeClassOld = aceEditor.renderer.theme.cssClass;
                aceEditor.setTheme(value, function(){ // asynchronous
                    var themeClassNew = aceEditor.renderer.theme.cssClass;
                    // This must be synced when ace editor theme is changed, not by directly listening theme property.
                    $('#consoleContent').removeClass(themeClassOld).addClass(themeClassNew);
                });
            } catch (e) {}
        });
    }

    function configureOutput () {
        //$('#consoleOutput').addClass($('#consoleInput').attr('class'));
        $('#consoleOutput').addClass('ace_editor');
        // This allows child-element #consoleOutputFakeGutter to be themed like .ace-tm .ace_gutter.
        $('#consoleContent').addClass('ace-tm');
        // Since the editor's gutter would be missing from the output, we imitate it.
        $('#consoleOutputFakeGutter').addClass('ace_gutter');
        // If the console input is smaller than the clickable free space, redirect clicks to focus the console input.
        $('#consoleContent').on('click', function(event) {
            if (event.target == $(this)[0]) console.focus();
        });
    }

    function getBasename (filepath) {
        return filepath.match(/(?:[^\\\/]+)?$/)[0];
    }

    function getDirname (filepath) {
        return filepath.slice(0, filepath.length - getBasename(filepath).length);
    }

    initialize(); // $(initialize);

    // Return the features API.
    return {
        settings: settings,
        console: console,
        output: output,
        editor: editor,
        consoleMenu: consoleMenu,
        editorMenu: editorMenu
    };
});
