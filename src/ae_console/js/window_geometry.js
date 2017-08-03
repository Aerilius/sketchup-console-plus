define([], function () {

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
    function getGeometry (input) {
        // TODO: check out whether [window.outerWidth, window.outerHeight] is cross-platform
        var x  = windowLeft(),
            y  = windowTop(),
            w  = windowWidth(),
            h  = windowHeight(),
            sw = window.screen.width,
            sh = window.screen.height;
        return [x, y, w, h, sw, sh];
    }
    
    return {
        getGeometry: getGeometry
    };
});
