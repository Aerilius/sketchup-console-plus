// The external API exposed to SketchUp.
define(['./app'], function (FeatureAPI) {

    /**
     * Add an error to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    function error (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'error';
        FeatureAPI.output.add(text, metadata);
    };

    /**
     * Add a warning to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    function warn (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'warn';
        FeatureAPI.output.add(text, metadata);
    };

    /**
     * Add a JavaScript error object to the output.
     * @param {Error} errorObject
     */
    function javaScriptError (errorObject) {
        if (errorObject.number) {
            errorObject.lineNumber = errorObject.number;
        }
        if (errorObject.fileName == window.location.href && errorObject.lineNumber == 1) {
            errorObject.fileName = '(eval)';
        }
        var backtrace = [];
        if (errorObject.stack) {
            var backtrace = errorObject.stack.split('\n');
            backtrace.shift(); // First line contains error message.
        } else if (errorObject.fileName) {
            backtrace = [
                decodeURIComponent(
                    errorObject.fileName.replace(/^file\:\/\/(\/(?=\w\:))?/, "")
                ) + ": " + errorObject.lineNumber + ':' + errorObject.columnNumber
            ]
        }
        var message = '(JavaScript) ' + errorObject.name + ": " + errorObject.message;
        error(message, {language: 'javascript', backtrace: backtrace});
    };

    /**
     * Add puts stdout to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    function puts (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'puts';
        FeatureAPI.output.add(text, metadata);
    };

    /**
     * Add print stdout to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    function print (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'print';
        FeatureAPI.output.add(text, metadata);
    };

    return {
        error: error,
        warn: warn,
        javaScriptError: javaScriptError,
        puts: puts,
        print: print
    };
});
