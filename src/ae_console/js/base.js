/*
 AE JavaScript Library for SketchUp WebDialogs (extract)
 Version:      1.1.5
 Date:         08.05.2014
 Summary:
 module AE

 .$(pattern, scope)

 module Style
 .hasClass(HTMLElement, className)
 .addClass(HTMLElement, className)
 .removeClass(HTMLElement, className)
 .show(HTMLElement)
 .hide(HTMLElement)
 .setRule(selector, properties)

 module Events
 .bind(HTMLElement, eventName, function)

 module Form
 .fill(hash, HTMLFormElement, autoupdate)
 .read(HTMLFormElement)

 */


/**
 * @namespace
 */
var AE = function (AE) {

    var isDebugging = false;

    /**
     * Enables debugging of Bridge for browsers without skp protocol.
     * Overrides the internal message handler of Bridge.
     * Bridge skp requests are redirected to the browser's console or prompts if necessary.
     */
    AE.debugOutsideSketchUp = function() {
        isDebugging = true;
        Bridge.requestHandler = function(message, resolve, reject){
            var request = 'skp:' + message.name + '(' + JSON.stringify(message.arguments).slice(1, -1) + ')'
            if (message.expectsCallback) {
                // Show the request as alert.
                var question = 'Give a return value in JSON notation:',
                    resultString = prompt(request + "\n" + question);
                if (typeof resultString === 'string') {
                    result = JSON.parse(resultString);
                    // Resolve the query and return the result to it.
                    if (typeof resolve === 'function') resolve(result);
                } else {
                    // Otherwise reject the query.
                    if (typeof reject === 'function') reject("rejected");
                }
            } else {
                // Just log the call.
                console.log(request);
            }
            // Acknowledge that the message has been received and enable the bridge to send the next message if
            // available.
            Bridge.__ack__();
        };
    };


    /**
     * Tells whether debugging is enabled.
     * @returns {boolean}
     */
    AE.isDebugging = function() {
        return isDebugging;
    };


    /**
     * @const PLATFORM
     */
    AE.PLATFORM = (navigator.appVersion.indexOf("Win") != -1) ? "WIN" : ((navigator.appVersion.indexOf("OS X") != -1) ? "OSX" : "other");
    AE.RUBY_VERSION = 0;     // Needs to be set from SketchUp.
    AE.SKETCHUP_VERSION = 0; // Needs to be set from SketchUp.


    /**
     * @module Translate
     * Stub module for the case that no translation has been loaded.
     */
    if (!AE.Translate) {
        AE.Translate = {
            get: function (s) {
                return s;
            }
        };
    }


    /**
     * Selector function.
     * @param {string} pattern - a string that contains  #id,  .class  or  element
     * @param {HTMLElement} [scope] - element into which the search should be limited
     * @returns {HTMLElement,Array<HTMLElement>} single element (if #id given) or array of elements
     */
    AE.$ = function (pattern, scope) {
        // If no scope is given, elements are searched within the whole document.
        if (!scope) {
            scope = document;
        }
        //
        var results = [],
        // This supports several selectors (ie. comma-separated, no nesting).
            selectors = pattern.split(/\s*?,\s*?/);
        for (var s = 0; s < selectors.length; s++) {
            var selector = selectors[s];
            // ID
            if (selector.charAt(0) === "#") {
                var e = scope.getElementById(selector.slice(1));
                if (selectors.length > 1) {
                    results.push(e);
                    // Since ID should be used only once, this selection is unambiguous and we return the element directly.
                } else {
                    return e;
                }
                // Class
            } else if (selector.charAt(0) === ".") {
                // Modern browsers
                if (document.getElementsByClassName) {
                    results = results.concat(Array.prototype.slice.call(scope.getElementsByClassName(selector.slice(1))));
                    // Older browsers
                } else {
                    var cs = scope.getElementsByTagName("*");
                    if (cs.length === 0) {
                        continue;
                    }
                    var regexp = new RegExp('\\b' + selector.slice(1) + '\\b', 'gi');
                    for (var i = 0; i < cs.length; i++) {
                        if (cs[i].className.search(regexp) !== -1) {
                            results.push(cs[i])
                        }
                    }
                }
                // [property=value]
            } else if (selector.charAt(0) === "[" && selector.slice(-1) === "]") {
                var attribute = selector.match(/[^\[\]\=]+/)[0];
                var value = selector.match(/\=[^\]]+(?=\])/);
                if (value !== null) {
                    value = value[0].slice(1)
                }
                var cs = scope.getElementsByTagName("*");
                if (cs.length === 0) {
                    continue;
                }
                for (var i = 0; i < cs.length; i++) {
                    var val = cs[i].getAttribute(attribute);
                    if (val !== null && ((value !== null) ? (val === value) : true)) {
                        results.push(cs[i])
                    }
                }
                // TagName
            } else {
                var cs = scope.getElementsByTagName(selector);
                for (var i = 0; i < cs.length; i++) {
                    results.push(cs[i]);
                }
            }
        }
        return results;
    };


    /**
     * @module Style:
     * Custom methods to access/manipulate style-related things.
     */
    AE.Style = (function (self) {


        /**
         * Check if an element has a specific class.
         * @param {HTMLElement} element
         * @param {string} className
         * @returns {boolean}
         */
        self.hasClass = function (element, className) {
            if (!element || !element.className || !className) {
                return false;
            }
            var r = new RegExp("(^|\\b)" + className + "(\\b|$)");
            return r.test(element.className);
        };


        /**
         * Add a class to an element.
         * @param {HTMLElement} element
         * @param {string} className
         */
        self.addClass = function (element, className) {
            if (!element || !className) {
                return;
            }
            if (!element.className) {
                element.className = ""
            }
            if (!self.hasClass(element, className)) {
                element.className += (element.className !== '' ? ' ' : '') + className;
            }
        };


        /**
         * Remove a class from an element.
         * @param {HTMLElement} element
         * @param {string} className
         */
        self.removeClass = function (element, className) {
            if (!element || !element.className || !className) {
                return false;
            }
            var r = new RegExp("(^\\s*|\\s*\\b)" + className + "(\\b|$)", "gi");
            element.className = element.className.replace(r, "");
        };


        /**
         * Show an element. (using display)
         * @param {HTMLElement} element
         */
        self.show = function (element) {
            if (!element) {
                return;
            }
            if (element.style.display === "none") {
                element.style.display = element.original_display || "block";
            }
        };


        /**
         * Hide an element. (using display)
         * @param {HTMLElement} element
         */
        self.hide = function (element) {
            if (!element || element.style.display == "none") {
                return;
            }
            // Remember the original display property because it could be block, inline-block, inline etc.
            element.original_display = element.style.display;
            element.style.display = "none";
        };


        /**
         * Set a CSS rule
         * @param {string} selector
         * @param {object} properties
         */
        self.setRule = function (selector, properties) {
            var sheets = document.styleSheets;
            try {
                for (var i = 0; i < sheets.length; i++) {
                    var rules = sheets[i].cssRules || sheets[i].rules; // Mozilla || IE
                    for (var j = 0; j < rules.length; j++) {
                        if (rules[j].selectorText == selector) {
                            for (prop in properties) {
                                rules[j].style[prop] = properties[prop];
                            }
                            return;
                        }
                    }
                }
            } catch (e) {}
            // If an (security) error happens or a rule with matching selector doesn't exist, create a new one
            // See: http://code.google.com/p/chromium/issues/detail?id=49001
            if (sheets[0].insertRule) {
                var props = [];
                for (prop in properties) {
                    props.push(prop + ": " + properties[prop]);
                }
                try {
                    sheets[0].insertRule(selector + " {" + props.join("; ") + "}", 0);
                } catch (e) {}
            } else if (sheets[0].addRule) { // IE
                for (prop in properties) {
                    sheets[0].addRule(selector, prop + ":" + properties[prop], 0);
                }
            }
        };


        return self;
    }(AE.Style || {})); // end @module Style


    /**
     * @module
     * Methods for Events.
     */
    AE.Events = (function (self) {


        /**
         * Bind an event handler to an element.
         * @param {HTMLElement} element
         * @param {string} eventType
         * @param {function(Event)} fn
         */
        self.bind = function (element, eventType, fn) {
            if (!element || typeof eventType !== "string" || typeof fn !== "function") {
                return;
            }
            var fn2 = function (event) {
                if (!event) {
                    var event = window.event;
                }
                if (event.srcElement) {
                    event.target = event.srcElement;
                }
                if (!event.stopPropagation) {
                    event.stopPropagation = function () {
                        try {
                            event.cancelBubble = true;
                        } catch (e) {
                        }
                    }
                }
                if (!event.preventDefault) {
                    event.preventDefault = function () {
                        event.returnValue = false;
                    }
                }
                fn.apply(element, [event]);
            };
            if (document.addEventListener) {
                element.addEventListener(eventType, fn2, false);
                return true;
            } else if (document.attachEvent) {
                return element.attachEvent("on" + eventType, fn2);
            }
        };
        return self;


    }(AE.Events || {})); // end @module Events


    /**
     * @module
     * Methods to interact with Forms in the WebDialog and Ruby.
     */
    AE.Form = (function (self) {


        /**
         * Load default data into form elements.
         * Identifies input elements when their name matches the default's name.
         * @param {object<string,value>} hash - assigns to the input's name a value (string or boolean)
         * @param {HTMLElement=} form
         * @param {boolean=} autoupdate - whether changes to a form element should be transmitted immediately to SketchUp.
         */
        self.fill = function (hash, form, autoupdate) {
            if (!form) {
                form = document.getElementsByTagName("form")[0] || document.body
            }
            // Collect all input elements.
            var inputs = AE.$("input", form).concat(AE.$("select", form));
            // Loop over every input element and set its value.
            for (var i = 0; i < inputs.length; i++) {
                var input = inputs[i];
                // Since we don't use hyphens in Ruby Symbols, we normalize input names as well.
                var name = input.name.replace(/\-/, "_");
                // If options contain a key that matches the input's name; radios only when the value matches.
                if ((name in hash) && (input.type === "radio" && hash[name] === input.value || input.type !== "radio")) {
                    input.original_value = hash[name];
                    // Checkbox
                    if (input.type === "checkbox") {
                        input.checked = hash[name];
                    }
                    // Radio
                    else if (input.type === "radio") {
                        input.checked = true;
                    }
                    // Multiple select
                    else if (input.type === "select-multiple" && hash[name] !== null && hash[name].constructor() === Array) {
                        for (var j = 0; j < input.length; j++) {
                            for (var k = 0; k < hash[name].length; k++) {
                                if (input[j].value === hash[name][k]) {
                                    input[j].selected = true
                                }
                            }
                        }
                    }
                    // Text or select
                    else {
                        input.value = hash[name];
                    }
                }
                // Optionally add an event handler to update the key/value in Ruby.
                if (autoupdate === true && input.name && input.name !== "") {
                    var fn = function (name, input) {
                        return function () {
                            var newValue = getValue(input);
                            if (typeof input.original_value !== "undefined" && typeof input.original_value !== typeof newValue) {
                                input.value = input.original_value;
                                return input.original_value;
                            }
                            input.original_value = newValue;
                            var hash = {};
                            hash[name] = newValue;
                            Bridge.call('update_options', hash);
                        };
                    }(name, input);
                    if (input.addEventListener) {
                        input.addEventListener("change", fn, false);
                    } else if (input.attachEvent) {
                        input.attachEvent("onchange", fn);
                        // In IE we add an onclick event, otherwise changes on checkboxes trigger
                        // only onchange when blurring the element.
                        input.attachEvent("onclick", fn);
                    }
                }
            }
        };

        /**
         * Read user input from input elements.
         * Identifies key names from the name attribute of input elements.
         * @param {HTMLElement=} form
         * @returns {object<string,value>}
         */
        self.read = function (form) {
            if (!form) {
                form = document.getElementsByTagName("form")[0] || document.body
            }
            // Collect all input elements.
            var inputs = AE.$("input", form).concat(AE.$("select", form));
            // Loop over every input element and collect its value.
            var hash = {}, val = null;
            for (var i = 0; i < inputs.length; i++) {
                var input = inputs[i];
                // Continue only if the input is enabled and has a name.
                if (input.disabled || !input.name || input.name === "") {
                    continue;
                }
                val = getValue(input);
                if (val !== null) {
                    hash[input.name] = getValue(input);
                }
            }
            return hash;
        };


        /**
         * Function to get and validate data from a single input element
         * @param {HTMLInputElement} input
         * @returns {object} - Value of the input element (string, number or boolean)
         * @private
         */
        var getValue = function (input) {
            var val = null;
            // Make sure it responds to input's methods (better: is an HTMLInputElement).
            if (!input || !input.type || typeof input.value === "undefined" || input.value === null) {
                return null;
            }
            // Checkbox: Boolean true/false
            if (input.type === "checkbox") {
                val = input.checked;
            }
            // Radio checked: value as Symbol
            else if (input.type === "radio" && input.checked) {
                val = input.value;
            }
            else if (input.type === "radio" && !input.checked) {
            }
            // Text that is number: Numeric
            else if (!isNaN(input.value) && ((input.type === "text" || input.type === "select-one") && /\b(num|number|numeric|fixnum|integer|int|float)\b/i.test(input.className) || input.type === "number")) {
                // [optional] Use html5 step attribute or classNames to distinguish between Integer and Float input.
                if (input.step && (input.step % 1) === 0 || input.className && /\b(fixnum|integer|int)\b/i.test(input.className)) {
                    val = parseInt(input.value);
                } else { // if (input.step && (input.step%1) !== 0 || input.className && /\bfloat\b/i.test(input.className)) {
                    val = parseFloat(input.value);
                }
            }
            // Select multiple: Array of Strings
            else if (input.type === "select-multiple") {
                var s = [];
                for (var j = 0; j < input.length; j++) {
                    if (input[j].selected) {
                        s.push(input[j].value)
                    }
                }
                val = s;
            }
            // Text or select: String
            else {
                val = String(input.value);
            }
            return val;
        };


        return self;
    }(AE.Form || {})); // end @module Form


    /**
     * @module
     * Methods to interact with the browser window.
     */
    AE.Window = (function (self) {


        function viewportWidth () {
            return (typeof window.innerWidth !=='undefined') ? window.innerWidth : // with scrollbar
                document.documentElement.clientWidth;
        }


        function viewportHeight () {
            return (typeof window.innerHeight !=='undefined') ? window.innerHeight : // with scrollbar
                document.documentElement.clientHeight;
        }


        function viewportLeft () {
            return ('screenX' in window) ? window.screenX : window.screenLeft; // Note: window.screenLeft fails in WIE.
        }


        function viewportTop () {
            return ('screenY' in window) ? window.screenY : window.screenTop; // Note: window.screenTop fails in WIE.
        }


        function windowWidth () {
            return viewportWidth();
        }


        function windowHeight () {
            return viewportHeight();
        }


        function windowLeft () {
            return viewportLeft();
        }


        function windowTop () {
            return viewportTop();
        }


        var documentWidth = function() {
            return Math.round(document.body.getBoundingClientRect().left+document.body.getBoundingClientRect().right);
        };


        /**
         * Function to query window geometry.
         * @param {HTMLInputElement} input
         * @returns {object} - Value of the input element (string, number or boolean)
         * @private
         */
        self.getGeometry = function (input) {
            // TODO: check out whether [window.outerWidth, window.outerHeight] is cross-platform
            var x  = windowLeft(),
                y  = windowTop(),
                w  = windowWidth(),
                h  = windowHeight(),
                sw = window.screen.width,
                sh = window.screen.height;
            return [x, y, w, h, sw, sh];
        };


        return self;
    }(AE.Window || {})); // end @module Window


    return AE;
}(AE || {}); // end @module AE
