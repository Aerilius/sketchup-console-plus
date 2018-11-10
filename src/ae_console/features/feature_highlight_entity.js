requirejs(['app', 'bridge', 'ace/ace'], function (app, Bridge, ace) {

    /**
     * HighlightEntity
     * This highlights SketchUp entities and points and colors when hovering the console.
     */

    // Add CSS rules
    var className = 'highlight_entity';
    ace.require('ace/lib/dom').importCssString("\
.highlight_entity {             \
    border: 1px solid #eeeeee;  \
    border-color: rgba(200, 200, 200, 0.3);\
    margin: -1px;               \
    display: inline-block;      \
}                               \
                                \
.highlight_entity:hover {       \
    color: Highlight;           \
    border-color: Highlight;    \
}                               \
");

    function stop () {
        Bridge.call('highlight_stop');
    }

    var regexpEntity       = /#(?:<|&lt;|&#60;)Sketchup\:\:(?:Face|Edge|Curve|ArcCurve|Image|Group|ComponentInstance|ComponentDefinition|Text|Drawingelement|ConstructionLine|ConstructionPoint|Vertex)\:([0-9abcdefx]+)(?:>|&gt;|&#62;)/,
        regexpBoundingBox  = /#(?:<|&lt;|&#60;)Geom\:\:BoundingBox\:([0-9abcdefx]+)(?:>|&gt;|&#62;)/,
        regexpPoint        = /Point3d\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpPointString  = /(?!Point3d)\(([0-9\.\,\-eE]+)(?:m|\"|\'|cm|mm),[\s\u00a0]*([0-9\.\,\-eE]+)(?:m|\"|\'|cm|mm),[\s\u00a0]*([0-9\.\,\-eE]+)(m|\"|\'|cm|mm)\)/,
        regexpVector       = /Vector3d\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpVectorString = /\(([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+),[\s\u00a0]*([0-9\.\-eE]+)\)/,
        regexpColor        = /Color\(([\s\u00a0]*[0-9\.]+,[\s\u00a0]*[0-9\.]+,[\s\u00a0]*[0-9\.]+)(,[\s\u00a0]*[0-9\.]+)?\)/,
        regexpColorInspect = /#(?:<|&lt;|&#60;)Sketchup\:\:Color\:([0-9abcdefx]+)(?:>|&gt;|&#62;)/;

    function detectVisualizableElements(htmlElement) {
        $(htmlElement).find('.ace_sketchup').each(function(index, element) {
            var $element = $(element);
            var text = $element.text();
            if (regexpEntity.test(text) || regexpBoundingBox.test(text)) {
                addEntityHighlight($element, RegExp);
            } else if (regexpPoint.test(text)) {
                addPointWithoutUnitsHighlight($element, RegExp);
            } else if (regexpPointString.test(text)) {
                addPointWithUnitsHighlight($element, RegExp);
            } else if (regexpVector.test(text) || regexpVectorString.test(text)) {
                addVectorHighlight($element, RegExp);
            } else if (regexpColor.test(text)) {
                addColorHighlight($element, RegExp);
            } else if (regexpColorInspect.test(text)) {
                addColorInspectHighlight($element, RegExp);
            }
        });
    }

    function addEntityHighlight($element, regExp) {
        // Add highlight feature to SketchUp entities and get their id.
        var idString = regExp.$1;
        $element.addClass(className)
        .data('type', 'entity')
        .data('identifier', idString)
        .on('mouseover', function() { // Note: This can trigger repeatedly!
            Bridge.get('highlight_entity', idString)['catch'](function () {
                // If the entity isn't valid (deleted or GC), remove the highlight feature.
                $element.removeClass(className);
                $element.off('mouseover');
                $element.off('mouseout');
            });
        })
        .on('mouseout', stop);
    }

    function addPointWithoutUnitsHighlight($element, regExp) {
        // Add highlight feature to Point3d (without units: units = 'inch')
        var coordinates = [parseFloat(regExp.$1), parseFloat(regExp.$2), parseFloat(regExp.$3)];
        $element.addClass(className)
        .data('type', 'point')
        .data('identifier', [coordinates, 'inch'])
        .on('mouseover', function() {
            Bridge.call('highlight_point', coordinates);
        })
        .on('mouseout', stop);
    }

    function addPointWithUnitsHighlight($element, regExp) {
        // Add highlight feature to Point3d string with units
        var coordinates = $([regExp.$1, regExp.$2, regExp.$3]).map(function(index, coordinate){
            return parseFloat(coordinate.replace(/\,(?=[\d])/, '.'));
        });
        var units = regExp.$4;
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
        .data('type', 'point')
        .data('identifier', [coordinates, units])
        .on('mouseover', function() {
            Bridge.call('highlight_point', coordinates, units);
        })
        .on('mouseout', stop);
    }

    function addVectorHighlight($element, regExp) {
        // Add highlight feature to Vector3d or Vector3d string
        var coordinates = [parseFloat(regExp.$1), parseFloat(regExp.$2), parseFloat(regExp.$3)];
        $element.addClass(className)
        .data('type', 'vector')
        .data('identifier', coordinates)
        .on('mouseover', function() {
            Bridge.call('highlight_vector', coordinates);
        })
        .on('mouseout', stop);
    }

    function addColorHighlight($element, regExp) {
        // Add highlight feature to Color (only HTML/JS) 
        // when color has been printed as numerical color values.
        addColorHighlightToHTMLElement($element, 'rgb(' + regExp.$1 + ')');
    }

    function addColorInspectHighlight($element, regExp) {
        // Add highlight feature to Color (only HTML/JS)
        // when color has been printed as Ruby object with id.
        var idString = regExp.$1;
        Bridge.get('get_color', idString).then(function (colorArray) {
          addColorHighlightToHTMLElement($element, 'rgb(' + colorArray.slice(0, 3).join(',') + ')');
        }, function () {
            // If the entity isn't valid (deleted or GC), remove the highlight feature.
            $element.removeClass(className);
            $element.off('mouseover');
            $element.off('mouseout');
        });
    }

    function addColorHighlightToHTMLElement($element, colorString) {
        $element.addClass(className)
        .on('mouseover', function() {
            $(this).css('background-color', colorString);
        }).on('mouseout', function() {
            $(this).css('background-color', 'transparent');
        });
    }

    function detectContainerElements(htmlElement) {
        // Find arrays that contain only elements that can be visualized (SketchUp entities, points, vectors)
        // Begin of an array.
        var arrayStart = $(htmlElement).find('.ace_paren.ace_lparen'),
            arrayEnd,
            currentElement = arrayStart,
            nextElement,
            arrayElements = [],
            dataToHighlight = {
              entity: [],
              point: [],
              vector: []
            };
        while (true) {
            nextElement = currentElement.next(); // Or comma, but text nodes are ignored by jQuery.
            if (nextElement.length == 0) {
                // No element. Something is wrong, end the traversal.
                arrayElements.length = 0;
                break;
            } else if (nextElement.hasClass('highlight_entity')) { // or 'highlight_entity'
                // This is a visualizable element, add it.
                arrayElements.push(nextElement);
                dataToHighlight[nextElement.data('type')].push(nextElement.data('identifier'));
            } else if (nextElement.hasClass('ace_rparen')) {
                arrayEnd = nextElement;
                // End of the array.
                break;
            }
            currentElement = nextElement;
        }
        if (arrayElements.length != 0) {
            var contents = arrayStart.parent().contents(); // Includes text nodes
            contents.slice(contents.index(arrayStart), contents.index(arrayEnd)+1).wrapAll(
                $('<span>').addClass(className)
                .on('mouseenter', function() {
                    Bridge.call('highlight_multiple', dataToHighlight);
                }).on('mouseout', stop)
            );
        }
    }

    app.output.addListener('added', function (htmlElement, text, metadata) {
        if (metadata.type && /input|result|puts|print/.test(metadata.type) && !/javascript/.test(metadata.type)) {
            detectVisualizableElements(htmlElement);
            detectContainerElements(htmlElement);
        }
    });
});
