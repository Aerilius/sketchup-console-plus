requirejs(['app', 'ace/ace'], function (app, ace) {

    ace.require('ace/lib/dom').importCssString("\
#consoleOutput .message .time {  \
    display: none;               \
}                                \
#consoleOutput .message .trace { \
    position: absolute;          \
    top: 0;                      \
    right: 0;                    \
    opacity: 0.5;                \
}                                \
    ")

    function fileBaseName (filepath) {
        return filepath.match(/[^\\\/]*$/)[0];
    }

    function uriToPath (uri) {
        return decodeURI(uri).replace(/^file\:\//, '');
    }

    function commonSuffixRegExp (string) {
        return new RegExp('(' + string.split('').map(function (c) { return c.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&'); }).join('?') + ')');
    }

    app.output.addListener('added', function (entryElement, text, metadata) {
        if (/puts|print/.test(metadata.type)) {
            // Add right of the message body a shortlink for caller of puts/print.
            if (metadata.backtrace && metadata.backtrace.length > 0) {
                var trace = metadata.backtrace[0], match, path, lineNumber;
                // Extract the path and line number from the beginning of a trace.
                // example: /folders/file.rb:10: in `method_name'
                // Assuming the path contains at least one delimiter (to exclude '(eval)').
                match = trace.match(/^(.+[\/\\].+)\:(\d+)(?:\:.+)?$/);
                if (!match) return;
                path = match[1];
                lineNumber = parseInt(match[2]);
                var link = $('<a href="#">').on('click', function () {
                    app.editor.open(path, lineNumber);
                    app.settings.getProperty('console_active').setValue(false); // == app.switchToEditor();
                })
                .addClass('trace unselectable')
                .attr('data-text', fileBaseName(path) + ':' + lineNumber)
                .appendTo(entryElement);
            }
        } else if (/error|warn/.test(metadata.type)) {
            // Convert paths in backtrace into links.
            $('.backtrace *', entryElement).each(function (index, traceElement) {
                var path = $(traceElement).data('path');
                var lineNumber = $(traceElement).data('line-number');
                var columnNumber = $(traceElement).data('column-number');
                if (path && lineNumber) {
                    // Replace path:lineNumber(:columnNumber) by <a>path</a>:lineNumber(:columnNumber)
                    $(traceElement).html( $(traceElement).html().replace(commonSuffixRegExp(path), '<a href="#">$1</a>') )
                    // Add a clickable link.
                    .find('a').on('click', function () {
                        app.editor.open(uriToPath(path), lineNumber, columnNumber);
                        app.settings.getProperty('console_active').setValue(false); // == app.switchToEditor();
                    });
                }
            });
            // Add right of the message body a shortlink for first trace.
            if ($('.backtrace *', entryElement).length > 0) {
                var traceElement = $('.backtrace *', entryElement)[0];
                var path = uriToPath($(traceElement).data('path'));
                var lineNumber = $(traceElement).data('line-number');
                if (path && lineNumber) {
                    var link = $('<a href="#">').on('click', function () {
                        app.editor.open(path, lineNumber);
                        app.settings.getProperty('console_active').setValue(false); // app.switchToEditor();
                    })
                    .addClass('trace unselectable')
                    .attr('data-text', fileBaseName(path) + ':' + lineNumber)
                    .appendTo(entryElement);
                }
            }
        }
    });
});
