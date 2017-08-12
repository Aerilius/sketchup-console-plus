define(['jquery', './bridge'], function ($, Bridge) {
    function setZoom(zoom) {
        document.documentElement.style.zoom = zoom;
        $('iframe').css({
          'transform-origin': '0 0',
          'transform': 'scale('+zoom+')',
          'width':  (100/zoom)+'%',
          'height': (100/zoom)+'%'
        });
    }
    
    var zoom = 1.0;
    $(document).on('keydown', function (event) {
        if (event.ctrlKey) {
            switch (event.which) {
                case 48: // zero; keydown/keypress/keyup: 48; ctrl+0 keydown/keyup: 48
                    zoom = 1.0;
                    setZoom(zoom);
                    break;
                case 221: // plus; keydown/keyup: 221, keypress: 43; ctrl+ keydown/keyup: 221
                    zoom *= 1.25;
                    setZoom(zoom);
                    break;
                case 191: // minus; keydown/keyup: 191, keypress: 45; ctrl+minus keydown/keyup: 191
                    zoom *= 0.8;
                    setZoom(zoom);
                    break;
            }
        }
    });
});
