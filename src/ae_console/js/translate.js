define('translate', [], function () {
    /* Object containing all translation strings. */
    var STRINGS = {};
    var excluded = new RegExp('^(script|style)$', 'i');
    var emptyString = new RegExp('^(\n|\s|&nbsp;)+$', 'i');

    function load (strings) {
        for (var key in strings) {
            STRINGS[key] = strings[key];
        }
    }

    /* Method to access a single translation. */
    function get (key, s1, s2) {
        try {
            if (typeof key !== 'string') { return ''; }
            // Get the string from the hash and be tolerant towards punctuation and quotes.
            var value = key;
            if (key in STRINGS) {
                value = STRINGS[key];
            } else {
                var key2 = key.replace(/[\.\:]$/, '');
                if (key2 in STRINGS) {
                    value = STRINGS[key];
                }
            }
            // Substitution of additional strings.
            for (var i = 1; i < arguments.length; i++) {
                value = value.replace('%'+(i-1), arguments[i], 'g');
            }
            return value;
        } catch (e) {
            return key || '';
        }
    }

    /* Translate the complete HTML. */
    function html (root) {
        if (root==null) { root = document.body; }
        var textNodes = [];
        var nodesWithAttr = {'title': [], 'placeholder': [], 'alt': []};
        // Translate all found text nodes.
        getTextNodes(root, textNodes, nodesWithAttr);
        for (var i = 0; i < textNodes.length; i++) {
            var text = textNodes[i].nodeValue;
            if (text.match(/^\s*$/)) { continue; }
            // Remove whitespace from the source code to make matching easier.
            var key = String(text).replace(/^(\n|\s|&nbsp;)+|(\n|\s|&nbsp;)+$/g, '');
            var value = get(key);
            // Return translated string with original whitespace.
            textNodes[i].nodeValue = text.replace(key, value);
        }
        for (var attr in nodesWithAttr) {
            for (var i = 0; i < nodesWithAttr[attr].length; i++) {
                try {
                    var node = nodesWithAttr[attr][i];
                    node.setAttribute(attr, get( node.getAttribute(attr) ) );
                } catch(e) {}
            }
        }
    }

    /* Get all text nodes that are not empty. Get also all title attributes. */
    function getTextNodes (node, textNodes, nodesWithAttr) {
        if (node && node.nodeType === 1 && !excluded.test(node.nodeName)) {
            if (node.getAttribute('title') !== null && node.getAttribute('title') !== '') { nodesWithAttr['title'].push(node); }
            if (node.getAttribute('placeholder') !== null && node.getAttribute('placeholder') !== '') { nodesWithAttr['placeholder'].push(node); }
            for (var i = 0; i < node.childNodes.length; i++) {
                var childNode = node.childNodes[i];
                if (childNode && childNode.nodeType === 3 && !emptyString.test(childNode.nodeValue)) {
                    textNodes.push(childNode);
                } else {
                    getTextNodes(childNode, textNodes, nodesWithAttr);
                }
            }
        }
    }

    return {
        get: get,
        html: html,
        load: load
    };
});
