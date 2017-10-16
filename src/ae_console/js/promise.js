define([], function () {

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
    var Promise = function (executor) {
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
         *                                        Takes the promised result as parameter.
         * @param   {function(Error)}  onReject   A function to call when the promise is rejected.
         *                                        Takes the reason/error as parameter.
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
         *                                      Takes the reason/error as parameter.
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
         */
        function resolve (result) {
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
        }

        /**
         * Reject a promise once it cannot be resolved anymore or an error occured when calculating its result.
         * @param   {(string,Error)} reason
         */
        function reject (reason) {
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
        }

        if (typeof executor === 'function') {
            try {
                executor(resolve, reject);
            } catch (error) {
                reject(error);
            }
        }

    };

    Promise.resolve = function (value) {
        return new Promise(function(resolve, reject){ resolve(value) });
    };

    Promise.reject = function (value) {
        return new Promise(function(resolve, reject){ reject(value) });
    };

    Promise.all = function(promises) {
        if (Object.prototype.toString.call(promises) === '[object Array]') return Promise.reject(new TypeError('Argument must be iterable'));
        return new Promise(function (resolve, reject) {
            if (promises.length == 0) {
                resolve([]);
            } else {
                var pendingCounter = promises.length;
                var results = new Array(promises.length);
                for (var i = 0; i < promises.length; i++) {
                    if (typeof promises[i].then === 'function') {
                        promise.then(function (result) {
                            results[i] = result;
                            pendingCounter -= 1;
                            if (pendingCounter == 0) resolve(results);
                        }, reject); // reject will only run once
                    } else {
                        results[i] = promise; // if it is an arbitrary object, not a promise
                        pendingCounter -= 1;
                        if (pendingCounter == 0) resolve(results);
                    }
                }
            }
        });
    };

    Promise.race = function (promises) {
        if (Object.prototype.toString.call(promises) === '[object Array]') return Promise.reject(new TypeError('Argument must be iterable'));
        return new Promise(function (resolve, reject) {
            for (var i = 0; i < promises.length; i++) {
                if (typeof promises[i].then === 'function') {
                    promise.then(resolve, reject);
                }
            }
        });
    };
    
    return Promise;
});
