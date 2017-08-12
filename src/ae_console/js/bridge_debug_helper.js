define(['./bridge'], function (Bridge) {
    /**
     * Enables debugging of Bridge for browsers without skp protocol.
     * Overrides the internal message handler of Bridge.
     * Bridge skp requests are redirected to the browser's console or prompts if necessary.
     */
    var mockedCallbacks = {};

    function interactiveRequestHandler (message, resolve, reject) {
        var request = 'skp:' + message.name + '(' + JSON.stringify(message.arguments).slice(1, -1) + ')';
        if (message.expectsCallback) {
            // Respond to the request and call the callback.
            if (message.name in mockedCallbacks) {
                // Resolve the request automatically with mock data.
                window.console.log(request);
                var result;
                if (typeof mockedCallbacks[message.name] !== 'function') {
                    result = mockedCallbacks[message.name];
                    if (typeof resolve === 'function') resolve(result);
                    window.console.log('>> ' + JSON.stringify(result));
                } else {
                    try {
                        result = mockedCallbacks[message.name].apply(undefined, message.arguments);
                        if (typeof resolve === 'function') resolve(result);
                        window.console.log('>> ' + JSON.stringify(result));
                    } catch (error) {
                        if (typeof reject === 'function') {
                            reject(error);
                        } else {
                            window.console.error(error);
                        }
                    }
                }
            } else {
                // Show the request as prompt.
                var question = 'Give a return value in JSON notation:',
                    resultString = window.prompt(request + "\n" + question);
                if (typeof resultString === 'string') {
                    var result = JSON.parse(resultString);
                    // Resolve the query and return the result to it.
                    if (typeof resolve === 'function') resolve(result);
                } else {
                    // Otherwise reject the query.
                    if (typeof reject === 'function') reject("rejected");
                }
            }
        } else {
            // Just log the call.
            console.log(request);
        }
        // Acknowledge that the message has been received and enable the bridge 
        // to send the next message if available (for legacy skp Bridge with message pipe).
        if (Bridge.__ack__) Bridge.__ack__();
    }

    // By default, when this module is required, enable the debugging request handler.
    Bridge.requestHandler = interactiveRequestHandler;

    return {
        /**
         * This function adds mock data to automatically respond to bridge requests.
         * @param {Object.<string, *|function>} mocks  an object that assigns to a request name 
         *    either static response data or a function that returns response data.
         */
        mockRequests: function (mocks) {
            for (var key in mocks) {
                mockedCallbacks[key] = mocks[key];
            }
        }
    };
});
