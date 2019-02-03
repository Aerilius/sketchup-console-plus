define(['polyfills/es6-promise'], function (PromiseImplementation) {
    PromiseImplementation.polyfill();

    /**
     * @exports self as Bridge
     */
    var self = {};
    
    self.Promise = Promise;

    /**
     * The namespace prepended to all action callbacks and all internal handlers.
     * It must match this module's path.
     * @constant {string}
     */
    var NAMESPACE = 'Bridge';

    /**
     * Calls a Ruby handler.
     * @param {string}     name       The name of the Ruby action_callback.
     * @param {...object}  parameter  Any amount of parameters of JSON type.
     */
    self.call = function (name, parameter) {
        if (typeof name !== 'string') {
            throw new TypeError('Argument "name" must be a string');
        }
        var args, message;
        args = Array.prototype.slice.call(arguments).slice(1);
        message = {
                name: name,
                parameters: args,
                expectsCallback: false
            };
        // Pass it to the request handler.
        self.requestHandler(message);
    };

    /**
     * Sends a request to Ruby and gets the return value in a promise.
     * @param   {string}    name      The name of the Ruby action_callback.
     * @param   {...object} parameter Any amount of parameters of JSON type.
     * @returns {Promise}             A promise representing the return value of the Ruby callback.
     */
    self.get = function (name, parameter) {
        if (typeof name !== 'string') {
            throw new TypeError('Argument "name" must be a string');
        }
        var args = Array.prototype.slice.call(arguments).slice(1);
            var message = {
                name: name,
                parameters: args,
                expectsCallback: true
            };
        // Return the promise.
        return new Promise(function (resolve, reject) {
            self.requestHandler(message, resolve, reject);
        });
    };

    /**
     * Logs any text to the Ruby console.
     * @param {string} text
     */
    self.puts = function (text) {
        self.call(NAMESPACE + '.puts', text);
    };


    /**
     * Reports an error to the Ruby console.
     * @overload
     *   @param {string} textOrError
     *   @param {{filename: string, lineNumber: number, url: string, type: string}} metadata
     * @overload
     *   @param {Error}  textOrError
     *   @param {object} metadata
     */
    self.error = function (textOrError, metadata) {
        var type, message, trace, backtrace = [];
        metadata = metadata || {};
        if (typeof textOrError === 'string') {
            var text = textOrError; /** @type {string} */
            type = metadata.type || 'Error';
            message = text;
            trace = (metadata.filename) ? metadata.filename :
                (metadata.url) ? metadata.url :
                    (location.protocol == 'file:') ? location.pathname.match(/[^\/\\]+$/) :
                        location.href;
            if (metadata.lineNumber) {
                trace += ':' + metadata.lineNumber + ': in JavaScript function';
            }
            backtrace = [trace];
        } else if (textOrError instanceof Error) {
            var error = textOrError; /** @type {Error} */
            type = error.name;
            message = error.message || error.description;
            trace = (error.filename) ? error.filename :
                (location.protocol == 'file:') ? (location.pathname.match(/[^\/\\]+$/) || [])[0] :
                    location.href;
            if (error.lineNumber) {
                trace += ':' + error.lineNumber + ': in JavaScript function';
            }
            backtrace = [trace];
            if (error.stack) {
                backtrace = backtrace.concat(error.stack);
            }
        } else {
            throw new TypeError('Argument must be a String or Error');
        }
        self.call(NAMESPACE + '.error', type, message, backtrace);
    };

    /**
     * @name Message
     * @typedef Message
     * @type     {object}
     * @property {string}        name             The name of the remote function to call.
     * @property {Array<object>} parameters       An array of parameters in JSON-compatible, serializable format.
     * @property {boolean}       expectsCallback  Whether a handler is waiting to be called.
     * @property {number}        id               A unique message id to match its response to a JavaScript handler.
     * @private
     */
    /**
     * Handles requests to a remote server and the returned responses.
     * @param {Message}          message
     * @param {function(object)} resolve  A function to call on successful response from server / SketchUp.
     * @param {function(string)} reject   A function to call on error.
     * @private
     */
    self.requestHandler = (function () {

        /**
         * A unique identifier for each message. It is used to match return values from Ruby to JavaScript callbacks.
         * @type {number}
         * @private
         */
        var messageID = 0;

        /**
         * @name      Handler
         * @typedef   Handler
         * @type     {object}
         * @property {number}   id       The unique id of the message to which the handler belongs.
         * @property {string}   name     The name to identify the Ruby callback.
         * @property {function} resolve  The handler to be called on success via `Bridge.__resolve__(id, result)`.
         * @property {function} reject   The handler to be called on failure via `Bridge.__reject__(id, reason)`.
         * @private
         */

        /**
         * The set of callback handlers waiting to be called from Ruby.
         * @type {object.<number,Handler>}
         * @private
         */
        var handlers = {};

        /**
         * The remote end-point calls a JavaScript success handler.
         * @param  {number} id           The id of the JavaScript-to-Ruby message.
         * @param  {...object} parameter Any amount of parameters.
         * @private                      (only for use by corresponding Remote)
         */
        self.__resolve__ = function (id, parameter) {
            var args, handler;
            // If there is a callback handler, execute it.
            if (handlers[id]) {
                handler = handlers[id];
                args = Array.prototype.slice.call(arguments).slice(1);
                try {
                    if (typeof handler.resolve === 'function') {
                        handler.resolve.apply(undefined, args);
                    }
                } catch (error) {
                    error.message = NAMESPACE + '.__resolve__: Error when executing handler ' +
                        '`' + handler.name + '` (' + id + '): ' + error.message;
                    if (!error.stack) error.stack = handler.resolve.toString();
                    self.error(error);
                }
                delete handlers[id];
            }
        };

        /**
         * The remote end-point calls a JavaScript error handler.
         * @param  {number} id         The id of the JavaScript-to-Ruby message.
         * @param  {...reason} reason  Any amount of reasons or other parameters.
         * @private                    (only for use by corresponding Remote)
         */
        self.__reject__ = function (id, reason) {
            var reasons, handler;
            // If there is a callback, execute it.
            if (handlers[id]) {
                handler = handlers[id];
                reasons = Array.prototype.slice.call(arguments).slice(1);
                try {
                    if (typeof handler.reject === 'function') {
                        handler.reject.apply(undefined, reasons)
                    }
                } catch (error) {
                    error.message = NAMESPACE + '.__reject__: Error when executing handler ' +
                        '`' + handler.name + '` (' + id + '): ' + error.message;
                    self.error(error);

                }
                delete handlers[id];
            }
        };

        self.__create_error__ = function (type, message, stack) {
            var errorClass = window[type] || Error;
            var error = new errorClass(message);
            if (error.stack) error.stack = stack;
            return error;
        };

        if (typeof window.sketchup !== 'undefined') { // UI::HtmlDialog, SketchUp 2017+

            /**
             * Sends a message.
             * @param {Message} message
             */
            return function send (message, resolve, reject) {
                // We assign an id to this message so we can identify a callback (if there is one).
                var id = message.id = messageID++;
                handlers[id] = {
                    name: message.name,
                    resolve: resolve,
                    reject: reject
                };
                // Workaround issue: Failure to register new callbacks in Chromium, thus overwriting the existing, unused "LoginSuccess.
                window.sketchup['LoginSuccess'](message);
            };

        } else { // UI::WebDialog

            /**
             * The url which responds to requests.
             * @constant {string}
             */
            var URL_RECEIVE = 'skp:' + NAMESPACE + '.receive';

            /**
             * Remote tells the bridge that the most recently sent message has been received.
             * Enables the bridge to send the next message if available.
             * @param {number} [id]  The id of the message to be acknowledged.
             * @private              (only for use by corresponding Remote)
             */
            self.__ack__ = function (id) {
                running = false; // Ready to send new messages.
                cleanUpScripts();
                if (queue.length > 0) {
                    deQueue();
                }
            };

            /**
             * The queue of messages waiting to be sent.
             * SketchUp/macOS/Safari skips skp urls if they happen in a too short time interval.
             * We pass all skp urls through a queue that makes sure that a new message is only
             * sent after the SketchUp side has received the previous message and acknowledged it with `Bridge.__ack__()`.
             * @type {Array<Message>}
             * @private
             */
            var queue = [];

            /**
             * Whether the queue is running and fetches on its own new messages from the queue.
             * @type {boolean}
             * @private
             */
            var running = false;

            /**
             * A hidden input field for message data.
             * Since skp: urls have a limited length and don't support arbitrary characters, we store the complete message
             * data in a hidden input field and retrieve it from SketchUp with `UI::WebDialog#get_element_value`.
             */
            var requestField;

            function createMessageField (id) {
                var messageField = document.createElement('input');
                messageField.setAttribute('type', 'hidden');
                messageField.setAttribute('style', 'display: none');
                messageField.setAttribute('id', NAMESPACE + '.' + id);
                document.documentElement.appendChild(messageField);
                return messageField;
            }

            function cleanUpScripts () {
                var scripts = document.body.getElementsByTagName('script');
                for (var i = 0; i < scripts.length; i++) {
                    document.body.removeChild(scripts[i]);
                }
            }

            /**
             * Serializes an object.
             * For serializing/unserializing objects, we currently use JSON.
             * @param   {object} object  The object to serialize into a string.
             * @returns {string}
             */
            function serialize (object) {
                return JSON.stringify(object);
            }

            /**
             * Puts a new message into the queue.
             * If is not running, start it.
             * @param {Message}          message
             * @param {function(object)} resolve  A function to call on successful response from server / SketchUp.
             * @param {function(string)} reject   A function to call on error.
             * @private
             */
            function enQueue (message, resolve, reject) {
                // We assign an id to this message so we can identify a callback (if there is one).
                var id = message.id = messageID++;
                handlers[id] = {
                    name: message.name,
                    resolve: resolve,
                    reject: reject
                };
                queue.push(message);
                // If the queue is not running, start it.
                // If the message queue contains messages, then it is already running.
                if (!running) {
                    deQueue();
                }
            }

            /**
             * Fetches the next message from the queue and sends it.
             * If the queue is empty, set the queue not running / idle.
             * @private
             */
            function deQueue () {
                var message = queue.shift();
                if (!message) {
                    running = false;
                    return;
                }
                // Lock the status variable before sending the message.
                // (because window.location is synchronous in IE and finishes
                // before this function finishes.)
                running = true;
                send(message);
            }

            /**
             * Sends a message.
             * @param {Message} message
             */
            function send (message) {
                // Lazy initialization: On first call of the requestHandler, create the messageField.
                // Wait a timeout to make sure the DOM is loaded before creating the messageField. (Otherwise blank page)
                window.setTimeout(function () {
                    // Create the messageField.
                    requestField = createMessageField('requestField');
                    // Now replace this function by the implementation without initialization:
                    var sendImplementation = function (message) {
                        requestField.value = serialize(message);
                        // Give enough time to refresh the DOM, so that SketchUp will be able to
                        // access the latest values of messageField.
                        window.setTimeout(function () {
                            window.location.href = URL_RECEIVE;
                        }, 0);
                    };
                    send = sendImplementation;
                    sendImplementation(message);
                }, 0);
            }

            return enQueue;
        }
    })();

    window.Bridge = self; // Export this module purposefully as global.
    return self;
});
