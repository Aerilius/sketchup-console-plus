// The external API exposed to SketchUp.
AE.Console = new function() {
    // TODO: Merge this file with ui_bootstrap so they can have shared internals.
    var output;
    var extensions = [];
    var extensionAccess;

    this.addListener = function (eventName, fn) { // TODO: remove
        $(output).on(eventName, function (event, args) {
            fn.apply(undefined, args);
        });
    };

    function trigger (eventName, data) {
        var args = Array.prototype.slice.call(arguments).slice(1);
        $(output).trigger(eventName, [args]);
    }

    this.initialize = function (object) { // TODO: internal; why is this needed? Initialize API from ui_bootstrap.
    // What to do before api is ready?
        extensionAccess = object;
        output = extensionAccess.output;
        // Load queued extensions.
        var extensionInitializer;
        while (extensions.length > 0) {
            extensionInitializer = extensions.shift();
            if (typeof extensionInitializer == 'function') {
                extensionInitializer(extensionAccess);
            }
        }
    };


    /**
     * @name     ExtensionAccess
     * @typedef  ExtensionAccess
     * @type     {object}
     * @property {Console}  console
     * @property {Editor}   editor
     * @property {Output}   output
     * @property {Settings} settings
     * @property {Menu}     consoleMenu
     * @property {Menu}     editorMenu
     * @private
     */
    /**
     * Initializes an extension and passes to it the API objects.
     * @param {function(ExtensionAccess)} extensionInitializer
     */
    this.registerExtension = function (extensionInitializer) {
        // Queue extensions until the application is loaded.
        if (!extensionAccess) {
            extensions.push(extensionInitializer);
        } else {
            if (typeof extensionInitializer == 'function') {
                extensionInitializer(extensionAccess);
            }
        }
    };

    /**
     * Add input to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    /*this.input = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'input';
        trigger('input', text, metadata);
        if (output) output.add(text, metadata);
    };*/


    /**
     * Add a return value to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    /*this.result = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'result';
        trigger('result', text, metadata);
        if (output) output.add(text, metadata);
    };*/


    /**
     * Add an error to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    this.error = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'error';
        trigger('error', text, metadata);
        if (output) output.add(text, metadata);
    };


    /**
     * Add a warning to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    this.warn = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'warn';
        trigger('warn', text, metadata);
        if (output) output.add(text, metadata);
    };


    /**
     * Add a JavaScript error to the output.
     * @param {Error} error
     */
    this.javaScriptError = function (error) {
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
        var message = '(JavaScript) ' + error.name + ": " + error.message;
        this.error(message, {language: 'javascript', backtrace: backtrace});
    };


    /**
     * Add puts stdout to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    this.puts = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'puts';
        trigger('puts', text, metadata);
        if (output) output.add(text, metadata);
    };


    /**
     * Add print stdout to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    this.print = function (text, metadata) {
        if (!metadata) {
            metadata = {};
        }
        metadata.type = 'print';
        trigger('print', text, metadata);
        if (output) output.add(text, metadata);
    };
};


// TODO: remove if not needed anymore, refactor if needed for JavaScript console.
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
    //AE.Console.javaScriptError(error);
    Bridge && Bridge.puts('JavaScript Error: '+error.message+'('+error.fileName+':'+error.lineNumber+')') ||
              console.log('JavaScript Error: '+error.message+'('+error.fileName+':'+error.lineNumber+')');
    return false; //return true;
};