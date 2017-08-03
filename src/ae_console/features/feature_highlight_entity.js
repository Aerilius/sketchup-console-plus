requirejs(['app', 'bridge', 'ace/ace'], function (app, Bridge, ace) {

    /**
     * HighlightEntity
     * This highlights SketchUp entities and points and colors when hovering the console.
     */

    // Add CSS rules
    var className = 'highlight_entity';
    ace.require('ace/lib/dom').importCssString("\
.highlight_entity {             \
    border: 1px solid lightgray;\
    display: inline-block;      \
}                               \
                                \
.highlight_entity:hover {       \
    color: Highlight;           \
    border-color: Highlight;    \
}                               \
")

    function stop () {
        Bridge.call('highlight_stop');
    }

    var regexpEntity       = /#(?:<|&lt;|&#60;)Sketchup\:\:(?:Face|Edge|Curve|ArcCurve|Image|Group|ComponentInstance|ComponentDefinition|Text|Drawingelement|ConstructionLine|ConstructionPoint|Vertex)\:([0-9abcdefx]+)(?:>|&gt;|&#62;)/,
        regexpBoundingBox  = /#(?:<|&lt;|&#60;)Geom\:\:(?:BoundingBox)\:([0-9abcdefx]+)(?:>|&gt;|&#62;)/,
        regexpPoint        = /Point3d\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpPointString  = /(?!Point3d)\(([0-9\.\,\-eE]+)(?:m|\"|\'|cm|mm),[\s\u00a0]*([0-9\.\,\-eE]+)(?:m|\"|\'|cm|mm),[\s\u00a0]*([0-9\.\,\-eE]+)(m|\"|\'|cm|mm)\)/,
        regexpVector       = /Vector3d\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpVectorString = /\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpColor        = /Color\(([\s\u00a0]*[0-9\.]+,[\s\u00a0]*[0-9\.]+,[\s\u00a0]*[0-9\.]+)(,[\s\u00a0]*[0-9\.]+)?\)/;

    app.output.addListener('added', function (htmlElement, text, metadata) {
        if (metadata.type && /input|result|puts|print/.test(metadata.type) && !/javascript/.test(metadata.type)) {
            $(htmlElement).find('.ace_sketchup').each(function(index, element){
                var $element = $(element);
                var text = $element.text();

                if (regexpEntity.test(text) || regexpBoundingBox.test(text)) {
                    // Add highlight feature to SketchUp entities and get their id (which is for some reason 2 * the Ruby object_id)
                    var id = parseInt(RegExp.$1) >> 1;
                    $element.addClass(className)
                    .on('mouseover', function() { // Note: This can trigger repeatedly times!
                        Bridge.get('highlight_entity', id)['catch'](function () {
                            // If the entity isn't valid (deleted or GC), remove the highlight feature.
                            $element.removeClass(className);
                            $element.off('mouseover');
                            $element.off('mouseout');
                        });
                    })
                    .on('mouseout', stop);

                } else if (regexpPoint.test(text)) {
                    // Add highlight feature to Point3d (without units: inch = " = \u0022 )
                    var coordinates = [parseFloat(RegExp.$1), parseFloat(RegExp.$2), parseFloat(RegExp.$3)];
                    $element.addClass(className)
                    .on('mouseover', function() {
                        Bridge.call('highlight_point', coordinates);
                    })
                    .on('mouseout', stop);

                } else if (regexpPointString.test(text)) {
                    // Add highlight feature to Point3d string
                    var coordinates = $([RegExp.$1, RegExp.$2, RegExp.$3]).map(function(coordinate){
                        return parseFloat(coordinate.replace(/\,(?=[\d])/, '.'));
                    });
                    var units = RegExp.$4;
                    // Replace unit names so they don't need escaping.
                    switch (units) {
                        case '"':
                            units = 'inch';
                            break;
                        case "'":
                            units = 'feet';
                            break;
                    }
                    $element.addClass(className)
                    .on('mouseover', function() {
                        Bridge.call('highlight_point', coordinates, units);
                    })
                    .on('mouseout', stop);

                } else if (regexpVector.test(text) || regexpVectorString.test(text)) {
                    // Add highlight feature to Vector3d or Vector3d string
                    var coordinates = [parseFloat(RegExp.$1), parseFloat(RegExp.$2), parseFloat(RegExp.$3)];
                    $element.addClass(className)
                    .on('mouseover', function() {
                        Bridge.call('highlight_vector', coordinates);
                    })
                    .on('mouseout', stop);

                } else if (regexpColor.test(text)) {
                    // Add highlight feature to Color (only HTML/JS)
                    var color = 'rgb(' + RegExp.$1 + ')';
                    $element.addClass(className)
                    .on('mouseover', function() {
                        $(this).css('background-color', color);
                    }).on('mouseout', function() {
                        $(this).css('background-color', 'none');
                    });
                }
            });
        }
    });
});
