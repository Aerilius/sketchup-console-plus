// Before loading requirejs.
var requirejs = {
    baseUrl: '../js', /* relative to html directory */
    paths: {
        ace: '../external/ace',
        bootstrap: '../external/bootstrap/js/bootstrap',
        'bootstrap-notify': '../external/bootstrap-notify/bootstrap-notify',
        'bootstrap-filterlist': '../external/bootstrap-typeahead/bootstrap-filterlist',
        'bootstrap-typeahead': '../external/bootstrap-typeahead/bootstrap-typeahead',
        features: '../features',
        jquery: '../external/jquery/jquery',
        polyfills: '../external/polyfills'
    },
    // Declare dependencies of legacy libraries that don't use define / requirejs.
    shim: {
        bootstrap: {
            deps: ['jquery'],
            exports: '$'
        },
        'bootstrap-notify': {
            deps: ['jquery'],
            exports: 'jQuery.notify'
        },
        'bootstrap-filterlist': {
            deps: ['jquery', 'bootstrap-typeahead'],
            exports: 'jQuery.fn.filterlist'
        },
        'bootstrap-typeahead': {
            deps: ['jquery'],
            exports: 'jQuery.fn.typeahead'
        }
    }
};
