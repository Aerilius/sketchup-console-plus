define(['jquery', 'features/history_manager', 'bridge', 'settings', 'console_api', 'enable_zoom'], function ($, History, Bridge, Settings, API) {

    var rubyVersion = '2.0.0';
    //Bridge.get('ruby_version').then(function (actual) { rubyVersion = actual; });
    var history = new History();
    var settings = new Settings();

    function navigateTo (address) {
        history.registerItem(address);
        setUrl(address);
        autoHideNavigation();
    }

    function setUrl (address) {
        $('#content_frame').attr('src', address);
        $('#navigation_address').val(address);
    }

    function showErrorPage () {
        setUrl('./documentation_error_page.html'); // Don't add to history.
        showNavigation();
    }

    function showNavigation () {
        $('#navigation_wrapper').css('height', 'initial');
    }

    function autoHideNavigation () {
        $('#navigation_wrapper').css('height', '');
    }

    $(function () { // on DOMContentLoaded

        $('#navigation_backward').on('click', function () {
            if (history.canUndo()) {
                var address = history.undo();
                setUrl(address);
            }
        });

        $('#navigation_forward').on('click', function () {
            if (history.canRedo()) {
                var address = history.redo();
                setUrl(address);
            }
        });

        $('#navigation_address').on('keyup', function (event) {
            if (event.which == 13) { /* enter */
                var input, address;
                input = $(this).val();
                if (/^https?\:\/\/[a-zA-Z0-9\-\.]{3,}\.[a-zA-Z]{2,}/.test(input)) {
                    address = input;
                } else if (/^[a-zA-Z0-9\-\.]{3,}\.[a-zA-Z]{2,}/.test(input)) {
                    address = 'http://' + input;
                } else {
                    address = $('#search_engine').val().replace(/QUERY/, encodeURIComponent(input));
                }
                navigateTo(address);
            }
        });

        $('#navigation .bookmark').each(function (index, button) {
            $(button).on('click', function () {
                navigateTo($(this).attr('data-href'));
            });
        });

        Bridge.call('loaded');

        /*Bridge.get('get_settings').then(function (settings) {
            var Property = requirejs('lib/property');
            var searchEngineProperty = new Property('search_engine', settings['search_engine']);
            $('#search_engine').val(searchEngineProperty.getValue());
            $('#search_engine').on('change', function () {
                searchEngineProperty.setValue($(this).val());
            });
        });*/
        Bridge.get('get_settings').then(settings.load);
        settings.getProperty('search_engine', null).addListener('change', function (newValue) {
            searchEngineProperty.setValue($(this).val());
        });

    });

    // Catch uncaught errors in the WebDialog and send them to the console.
    // There are some errors by the ACE editor (when double-clicking or selection
    // that goes outside the editor) that would be silent in a normal Internet Explorer
    // but cause popups in SketchUp.
    window.onerror = function(messageOrEvent, source, lineNumber, columnNumber, errorObject) {
        window.console.log([messageOrEvent, source, lineNumber, columnNumber, errorObject]);
        if (!errorObject) {
            errorObject = new Error();
            errorObject.name = 'Error';
            errorObject.message = messageOrEvent;
            errorObject.fileName = source;
            errorObject.lineNumber = lineNumber;
            errorObject.columnNumber = columnNumber;
        }
        API.javaScriptError(errorObject);
        Bridge.puts('JavaScript Error: '+errorObject.message+'('+source+':'+lineNumber+':'+columnNumber+')');
        return true;
    };// TODO: remove

    return {
        navigateTo: navigateTo,
        showErrorPage: showErrorPage
    };
});

define('features/history_manager', [], function () {
    /**
     * History Manager
     * Cross-origin policy blocks history access in frames, like:
     *   frame.history.back();
     * Because of this we implement our own history.
     */
    return function () {
        var before = [];
        var current = null;
        var after = [];

        this.registerItem = function (item) {
            if (after.length > 0) after.length = 0; // clear
            if (current) before.push(current);
            current = item;
        };

        this.canUndo = function () {
            return before.length > 0;
        };

        this.undo = function () {
            if (current) after.push(current);
            current = before.pop();
            return current;
        };

        this.canRedo = function () {
            return after.length > 0;
        }

        this.redo = function () {
            if (current) before.push(current);
            current = after.pop();
            return current;
        };
    }
});
