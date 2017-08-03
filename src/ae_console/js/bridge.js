/**
 * Library to facilitate WebDialog communication with SketchUp's Ruby environment.
 *
 * @module  Bridge
 * @version 2.0.0
 * @date    2015-08-08
 * @author  Andreas Eisenbarth
 * @license MIT License (MIT)
 *
 * The callback mechanism provided by SketchUp with a custom protocol handler `skp:` has several deficiencies:
 *
 *  * Inproper Unicode support; looses properly escaped calls containing '; drops repeated properly escaped backslashes.
 *  * Maximum url length in the Windows version of SketchUp is 2083. (https://support.microsoft.com/en-us/kb/208427)
 *  * Asynchronous on OSX (it doesn't wait for SketchUp to receive a previous call) and can loose quickly sent calls.
 *  * Supports only one string parameter that must be escaped.
 *
 *   (as documented here: https://github.com/thomthom/sketchup-webdialogs-the-lost-manual)
 *
 * This Bridge provides an intuitive and safe communication with any amount of arguments of any JSON-compatible type and
 * a way to access the return value. It implements a message queue to ensure communication is sequential. It is based on
 * Promises which allow easy asynchronous and delayed callback paths for both success and failure.
 *
 * @example Simple call
 *   // On the Ruby side:
 *   bridge.on("add_image") { |dialog, image_path, point, width, height|
 *     @entities.add_image(image_path, point, width.to_l, height.to_l)
 *   }
 *   // On the JavaScript side:
 *   Bridge.call('add_image', 'http://www.photos.com/image/9895.jpg', [10, 10, 0], '2.5m', '1.8m');
 *
 * @example Log output to the Ruby Console
 *   Bridge.puts('Swiss "grüezi" is pronounced [ˈɡryə̯tsiː] and means "您好！" in Chinese.');
 *
 * @example Log an error to the Ruby Console
 *   try {
 *     document.produceError();
 *   } catch (error) {
 *     Bridge.error(error);
 *   }
 *
 * @example Usage with promises
 *   // On the Ruby side:
 *   bridge.on("do_calculation") { |promise, length, width|
 *     if validate(length) && validate(width)
 *       result = calculate(length)
 *       promise.resolve(result)
 *     else
 *       promise.reject("The input is not valid.")
 *     end
 *   }
 *   // On the JavaScript side:
 *   var promise = Bridge.get('do_calculation', length, width)
 *   promise.then(function(result){
 *     $('#resultField').text(result);
 *   }, function(failureReason){
 *     $('#inputField1').addClass('invalid');
 *     $('#inputField2').addClass('invalid');
 *     alert(failureReason);
 *   });
 *
 * TODO: require('es6-promise').polyfill(); ?
 * TODO: delayed __get__? or on? pass a Promise or callback function to a JavaScript method like ajax?
 * TODO: rename get? it should not be confused with HTTP request methods, because it acutally uses POST instead of GET
 */
var Bridge = function (window, document, JSON) {
    /**
     * @exports self as Bridge
     */
    var self = {};

    /**
     * The name space prepended to all action callbacks and all internal handlers.
     * It must match this module's path.
     * @constant {string}
     */
    var NAMESPACE = 'Bridge';

    /**
     * The url which responds to requests.
     * @constant {string}
     */
    var URL_RECEIVE = 'skp:' + NAMESPACE + '.receive';


    /**
     * Calls a Ruby handler and optionally passes the return value in a callback function.
     * @param {string}     name       The name of the Ruby action_callback.
     * @param {...object}  argument   Any amount of arguments of JSON type.
     * @param {function}  [callback]  A JavaScript function to execute after the action_callback.
     */
    self.call = function (name, argument, callback) {
        if (typeof name !== 'string') {
            throw new TypeError('Argument "name" must be a string');
        }
        var args, message;
        args = Array.prototype.slice.call(arguments).slice(1);
        callback = (typeof(args[args.length - 1]) === 'function') ? args.pop() : null;
        message = {
                name: name,
                arguments: args,
                expectsCallback: (callback != null)
            };
        // Pass it to the request handler.
        self.requestHandler(message, callback, undefined);
    };


    /**
     * Sends a request to Ruby and gets the return value in a promise.
     * @param   {string}    name      The name of the Ruby action_callback.
     * @param   {...object} argument  Any amount of arguments of JSON type.
     * @returns {Promise}             A promise representing the return value of the Ruby callback.
     */
    self.get = function (name, argument) {
        if (typeof name !== 'string') {
            throw new TypeError('Argument "name" must be a string');
        }
        var args = Array.prototype.slice.call(arguments).slice(1);
            var message = {
                name: name,
                arguments: args,
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
     * Calls a JavaScript function and returns the result into a Ruby promise.
     * @param  {string}   handlerName  The name of the Ruby callback handler that will receive the return value.
     * @param  {function} fn           The function to call.
     * @param  {Array}    arguments    The arguments to pass to the function.
     * @private                        (only for use by Ruby class Bridge)
     */
    // TODO
    self.__get__ = function (handlerName, fn, arguments) {
        try {
            var returnValue = fn.apply(undefined, arguments);
            if (typeof returnValue['then'] === 'function') {
                returnValue.then(function (result) {
                    self.call(handlerName, true, result);
                }, function (reason) {
                    self.call(handlerName, false, reason);
                })
            } else {
                self.call(handlerName, true, returnValue);
            }
        } catch (error) {
            self.call(handlerName, false, error.name + ': ' + error.message);
        }
    };


    /**
     * @name Message
     * @typedef Message
     * @type     {object}
     * @property {string}        name             The name of the remote function to call.
     * @property {Array<object>} arguments        An array of arguments in JSON-compatible, serializable format.
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
         * The queue of messages waiting to be sent.
         * SketchUp/OSX/Safari skips skp urls if they happen in a too short time interval.
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


        function createMessageField(id) {
            var messageField = document.createElement('input');
            messageField.setAttribute('type', 'hidden');
            messageField.setAttribute('style', 'display: none');
            messageField.setAttribute('id', NAMESPACE + '.' + id);
            document.documentElement.appendChild(messageField);
            return messageField;
        }


        function cleanUpScripts() {
            var scripts = document.body.getElementsByTagName('script');
            for (var i = 0; i < scripts.length; i++) {
                document.body.removeChild(scripts[i]);
            }
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
        function deQueue() {
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
        function send(message) {
            // Lazy initialization: On first call of the requestHandler, create the messageField.
            // Wait a timeout to make sure the DOM is loaded before creating the messageField. (Otherwise blank page)
            window.setTimeout(function () {
                // Create the messageField.
                requestField = createMessageField('requestField');
                // Now replace this function by the implementation without intialization:
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
         * Remote calls a JavaScript success handler.
         * @param  {number} id           The id of the JavaScript-to-Ruby message.
         * @param  {...object} argument  Any amount of arguments.
         * @private                      (only for use by corresponding Remote)
         */
        self.__resolve__ = function (id, argument) {
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
                    if (!error.stack) error.stack = handler.resolve.toString(); // TODO
                    self.error(error);
                }
                delete handlers[id];
            }
        };


        /**
         * Remote calls a JavaScript error handler.
         * @param  {number} id         The id of the JavaScript-to-Ruby message.
         * @param  {...reason} reason  Any amount of reasons or other arguments.
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


        return enQueue;
    })();


    /**
     * Handles calls from the server to a function.
     * @param {object}           result   The result of a JavaScript function call
     * @param {function(object)} resolve  A function to call on successful response from server / SketchUp.
     * @param {function(string)} reject   A function to call on error.
     * TODO: error handling, use serialized arguments and apply?
     * @private
     */
    self.responseHandler = (function () {

        var responseField;

        function createMessageField(id) {
            var messageField = document.createElement('input');
            messageField.setAttribute('type', 'hidden');
            messageField.setAttribute('style', 'display: none');
            messageField.setAttribute('id', NAMESPACE + '.' + id);
            document.documentElement.appendChild(messageField);
            return messageField;
        }

        /**
         * Executes a function and prepares the response field.
         * @param {Message} message
         */
        function capture(result) {
            // Lazy initialization: On first call of the requestHandler, create the messageField.
            // Create the messageField.
            responseField = createMessageField('responseField');
            // Now replace this function by the implementation without intialization:
            var captureImplementation = function (result) {
                self.puts(serialize(result));
                responseField.value = serialize(result);
            };
            capture = captureImplementation;
            captureImplementation(result);
        }

        return capture;
    })();


    /**
     * Serializes an object.
     * For serializing/unserializing objects, we currently use JSON.
     * @param   {object} object  The object to serialize into a string.
     * @returns {string}
     */
    function serialize(object) {
        return JSON.stringify(object);
    }


    /**
     * Unserializes an object.
     * For serializing/unserializing objects, we currently use JSON.
     * @param   {string} string  The string of the serialized object.
     * @returns {object}
     */
    function unserialize(string) {
        return JSON.parse(string);
    }


    /**
     * Simple Promise implementation
     *
     * Run an asynchronous operation and return a promise that will receive the result.
     * @class Promise
     * @constructor
     * @param {function(function(object),function(Error))} [executor]
     *   An executor receives a function to resolve the promise with a result and a function to reject the promise
     *   in case of an error. The executor must call one such function.
     */
    var Promise = self.Promise = function (executor) {
        var STATE_PENDING  = 0,
            STATE_RESOLVED = 1,
            STATE_REJECTED = 2,
            state = STATE_PENDING,
            value = null,
            results = [],
            handlers = [],
            self = this;


        /**
         * Register an action to do when the promise is resolved.
         * @param   {function(object)} onFulfill  A function to call when the promise is resolved.
         *                                        Takes the promised result as argument.
         * @param   {function(Error)}  onReject   A function to call when the promise is rejected.
         *                                        Takes the reason/error as argument.
         * @returns {Promise}                     A new promise about that the on_resolve or
         *                                        on_reject block has been executed successfully.
         */
        this.then = function (onFulfill, onReject) {
            if (typeof onFulfill !== 'function' && typeof onReject !== 'function') {
                return this;
            }
            var nextPromise = new self.constructor(function (resolveNext, rejectNext) {
                handlers.push({
                    onFulfill:   onFulfill,
                    onReject:    onReject,
                    resolveNext: resolveNext,
                    rejectNext:  rejectNext
                });
            });
            switch (state) {
                case STATE_RESOLVED:
                    resolve.apply(undefined, results);
                    break;
                case STATE_REJECTED:
                    reject(value);
                    break;
            }
            return nextPromise;
        };


        /**
         * Register an action to do when the promise is rejected.
         * @param   {function(Error)} onReject  A function to call when the promise is rejected.
         *                                      Takes the reason/error as argument.
         * @returns {Promise}                   A new promise that the on_reject block has been executed successfully.
         */
        this['catch'] = function (onReject) {
            var nextPromise = new self.constructor(function (resolveNext, rejectNext) {
                handlers.push({
                    onReject:    onReject,
                    resolveNext: resolveNext,
                    rejectNext:  rejectNext
                });
            });
            switch (state) {
                case STATE_REJECTED:
                    reject(value);
                    break;
            }
            return nextPromise;
        };


        /**
         * Resolves a promise.
         * @param   {(Promise,object)} result
         * @returns {Promise}          This promise
         */
        var resolve = this.resolve = function (result) {
            if (state == STATE_PENDING) {
                // If this promise is resolved with another promise, the final result is not
                // known, so we add a thenable to the second promise to finish resolving this one.
                // TODO: is it consistent to change this promise's state to STATE_RESOLVED? It should not be
                // resolved a second time, but the final result is actually not really known.
                if (result && typeof result.then === 'function') { // result instanceof self.constructor
                    result.then(function (result) {
                        var results = Array.prototype.slice.call(arguments);
                        resolve.apply(undefined, results);
                    }, function (reason) {
                        reject(reason);
                    });
                    return;
                }
                results = Array.prototype.slice.call(arguments);
                value = results[0];
                state = STATE_RESOLVED;
            }
            var handler;
            var newResult;
            while (handlers.length > 0) {
                handler = handlers.shift();
                if (typeof(handler.onFulfill) === 'function') {
                    try {
                        newResult = handler.onFulfill.apply(undefined, results);
                        if (newResult && typeof newResult.then === 'function') {
                            newResult.then(handler.resolveNext, handler.rejectNext);
                        } else {
                            handler.resolveNext(newResult);
                        }
                    } catch (error) {
                        handler.rejectNext(error);
                    }
                } else { // No onFulfill registered.
                    handler.resolveNext.apply(undefined, results);
                }
            }
            return self;
        };
        this.fulfill = this.resolve;


        /**
         * Reject a promise once it cannot be resolved anymore or an error occured when calculating its result.
         * @param   {(string,Error)} reason
         * @returns {Promise}        This promise
         */
        var reject = this.reject = function (reason) {
            if (state == STATE_PENDING) {
                value = reason;
                state = STATE_REJECTED;
            }
            var handler;
            var newResult;
            while (handlers.length > 0) {
                handler = handlers.shift();
                if (typeof(handler.onReject) === 'function') {
                    try {
                        newResult = handler.onReject(reason);
                        if (newResult && typeof newResult.then === 'function') {
                            newResult.then(handler.resolveNext, handler.rejectNext);
                        } else {
                            handler.resolveNext(newResult);
                        }
                    } catch (error) {
                        handler.rejectNext(error);
                    }
                } else { // No onReject registered.
                    handler.rejectNext(reason);
                }
            }
            return self;
        };


        if (typeof executor === 'function') {
            try {
                executor(resolve, reject);
            } catch (error) {
                reject(error);
            }
        }


    };
    self.Promise.resolve = function(value) {
        return new self.Promise(function(resolve, reject){ resolve(value) });
    };
    self.Promise.resolve = function(value) {
        return new self.Promise(function(resolve, reject){ reject(value) });
    };


    return self;
}(window, document, JSON);