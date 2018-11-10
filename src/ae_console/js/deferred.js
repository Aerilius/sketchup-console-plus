define(['polyfills/es6-promise'], function (PromiseImplementation) {
    PromiseImplementation.polyfill();

    function Deferred () {
        var resolver, rejecter;
        this.promise = new Promise(function (_resolver, _rejecter) {
            resolver = _resolver;
            rejecter = _rejecter;
        });

        this.resolve = function () {
            resolver.apply(undefined, arguments);
        };

        this.reject = function () {
            rejecter.apply(undefined, arguments);
        };
    }
    
    return Deferred;
});
