/**
 * @name Settings
 * @typedef Settings
 * @class
 */
var Settings = function () {
    var settings = this,
        properties = {};


    this.addListener = function (eventName, fn) {
        $(settings).on(eventName, function (event, args) {
            fn.apply(undefined, args);
        });
        return settings;
    };


    function trigger (eventName, data) {
        var args = Array.prototype.slice.call(arguments).slice(1);
        $(settings).trigger(eventName, [args]);
        return settings;
    }


    /**
     * Retrieves a value of a property by its name.
     * If the property does not exist, the property is created with the given value.
     * @param   {string}  name       The name of the property
     * @param   {object}  value      The new value to setAn optional default value to return if the property does not
     * exist.
     * @returns {object}  The value
     */
    this.set = function (name, value) {
        properties[name] && properties[name].setValue(value) || addProperty(name, value);
        trigger(name, value); // TODO: check whether this can be removed (because we can listen properties directly)
    };


    /**
     * Retrieves a value of a property by its name.
     * If the property does not exist, an empty property is created.
     * @param   {string}  name          The name of the property
     * @param   {object=} defaultValue  An optional default value to return if the property does not exist.
     * @returns {object}  The value
     */
    this.get = function (name, defaultValue) {
        return properties[name] && properties[name].getValue() || defaultValue;
    };


    /**
     * Retrieves a property by its name.
     * If the property does not exist, an empty property is created.
     * @param   {string} name  The name of the property to retrieve
     * @returns {Property}
     */
    this.getProperty = function (name) {
        return properties[name] || addProperty(name, value);
    };


    /**
     * Check whether a property exists.
     * @param   {string}  name          The name of the property
     * @returns {boolean}  True if the property exists, false otherwise.
     */
    this.has = function (name) {
        return properties.hasOwnProperty(name);
    };


    /**
     * Sets many properties at once.
     * @param   {object}  _settings  An object literal containing strings as keys.
     */
    this.load = function (_settings) {
        $.each(_settings, function(name, value) {
            if (properties.hasOwnProperty(name)) {
                var property = properties[name];
                if (value != property.getValue()) property.setValue(value);
            } else {
                addProperty(name, value);
            }
        });
        trigger('load');
    };


    /*this.update = function (_settings) { // TODO: remove? should it ignore unknown properties or create them on the fly?
        $.each(_settings, function(name, value) {
            if (properties.hasOwnProperty(name)) {
                var property = properties[name];
                if (value != property.getValue()) property.setValue(value);
            }
        });
    };*/


    function addProperty(name, value) {
        var property = new Property(name, value);
        property.addListener('change', function(newValue){
            Bridge.call('update_property', name, newValue);
        });
        properties[name] = property;
        return property;
    }
};


/**
 *
 * @class
 */
var Property = function (_name, _value) {
    var property = this,
        name = _name,
        value = _value;


    this.addListener = function (eventName, fn) {
        $(property).on(eventName, function (event, args) {
            fn.apply(undefined, args);
        });
        return property;
    };


    /**
     * Adds an event listener and ensures the action is initially executed with the current property value.
     */
    this.bindAction = function (eventName, fn) {
        fn.apply(undefined, [value]);
        $(property).on(eventName, function (event, args) {
            fn.apply(undefined, args);
        });
        return property;
    };


    function trigger (eventName, data) {
        var args = [value];//Array.prototype.slice.call(arguments).slice(1);
        $(property).trigger(eventName, [args]);
    }


    this.getName = function () {
        return name;
    };


    this.setValue = function (newValue) {
        value = newValue;
        trigger('change', newValue);
    };


    this.getValue = function (defaultValue) {
        return value || defaultValue;
    };
};
