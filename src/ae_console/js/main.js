// Main function
requirejs(['app', 'bridge', 'console_api', 'jquery'], function (app, Bridge, API, $) {
    // 1. Load the app and UI (done)
    
    // 2. Publish 'Bridge' interface that the Ruby side will need to return from callbacks.
    // window.Bridge = Bridge; // This is now done with requirejs('bridge')

    // 3. Publish 'AE.Console' API interface on which the consoles on the Ruby side will call functions.
    window.AE = window.AE || {};
    window.AE.Console = API;

    // 4. Fallback for svg-resources to png images (this was for old Internet Explorer versions).
    $('img').on('error', function () {
        var img = $(this),
            src = img.attr('src');
        img.attr('src', src.replace(/\.svg$/, '.png'));
    });

    // 5. Catch uncaught errors in the WebDialog and send them to the console.
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
    };
});
