var AE = window.AE || {};

AE.Console = AE.Console || {};

AE.Console.Output = function(element, settings) {

    var output = this,
        $outputElement = $(element),
        nextMessageNewRow = true,
        $previousMessage = null;


    function initialize () {
        $outputElement.addClass('wrap_lines');
    }


    this.addListener = function (eventName, fn) {
        $(output).on(eventName, function (event, args) {
            fn.apply(undefined, args);
        });
    };


    function trigger (eventName, data) {
        var args = Array.prototype.slice.call(arguments).slice(1);
        $(output).trigger(eventName, [args]);
    }


    /**
     * Add an item to the output.
     * @param {string} text
     * @param {object=} metadata
     */
    this.add = function (text, metadata) {
        if (!metadata) metadata = {};
        metadata.type = metadata.type || 'other';
        metadata.language = metadata.language || settings.language;
        // Skip identical messages but increase the counter.
        if (/puts|print|error/.test(metadata.type) && nextMessageNewRow && text !== '\n' &&
            $previousMessage && $previousMessage.text && $previousMessage.counter &&
            text === $previousMessage.text) {
            //$previousMessage.('increaseCounter')(); // TODO
            return;
        }
        // Unfortunately SketchUp's stdout and stderr have only one `write` method
        // that prints inline text. To produce new lines (lik with `puts`), it sends
        // a single line break afterwards. In that case we receive a `print` with '\n'
        // and again a `print` with the message to put (stdout) or to put as error (stderr).
        // So we absorb the line break and let the next message start in a new line.
        if (/print|error/.test(metadata.type) && text === '\n') {
            // This case actually means "puts follows" or "error follows"
            nextMessageNewRow = true;
            return;
        } else if (/print/.test(metadata.type)) {
            // This is a real `print`.
            if (nextMessageNewRow) {
                createNewRow(text, metadata);
            } else {
                attach(text);
            }
            nextMessageNewRow = false;
        } else {
            // input, result, puts, warn, error
            createNewRow(text, metadata);
            nextMessageNewRow = true;
        }
    };


    /**
     * Clears the output.
     */
    this.clear = function () {
        $outputElement.empty();
    };


    /**
     * Insert text to the previous entry.
     * @param {string} text
     * @private
     */
    var attach = function (text) {
        $previousMessage.appendChild(document.createTextNode(text));
        // Update the attribute.
        $previousMessage.text += text;
    };


    /**
     * Creates a new entry.
     * @param {string} text
     * @param {object=} data
     * @private
     */
    var createNewRow = function (text, data) {
        if (typeof text !== 'string') return;
        data.text = text;

        var $div = $('<div>')
            .addClass('message')
            .addClass(data.type)
            //.addClass('ace_scroller ace_text-layer'); // Tweaks for ace. // TODO: Verify that ace_scroller is not
            // needed, it causes ugly drop shadow in ambiance theme.
            .addClass('ace_text-layer'); // Tweaks for ace.

        // Add gutter on the left side to continue the editor's gutter and for message channel indicators.
        // TODO: add line numbers
        var $gutter = $('<div>')
            .addClass('gutter')
            .addClass('ace-chrome ace_gutter'); // Tweaks for ace.
        $div.append($gutter);

        // Hook for raw text.
        trigger('beforeadded', data);

        // Add the code.
        var $code;
        if (/input|result/.test(data.type)) {
            $code = $('<code>')
                .addClass('content selectable');
            $previousMessage = $code;
            $code.data('text', data.text); // Save original text as attribute.
            $div.data('text', data.text);  // Save original text as attribute.
            data.html = output.highlight(data.text);
            // Hook for highlighted text.
            $code.html(data.html)
                .appendTo($div);
            trigger('afterCodeAdded', $code, data);

            // Add Error details.
        } else if (/error|warn/.test(data.type)) {
            // TODO: use bootstrap collapsible; currently disappears on click
            /*<button class="btn btn-primary" type="button" data-toggle="collapse" data-target="#collapseElementId"
             aria-expanded="false" aria-controls="collapseElementId">Header</button>
            <div class="collapse" id="collapseElementId">

             <div class="panel-group">
               <div class="panel panel-default">
                 <div class="panel-heading">
                   <h4 class="panel-title">
                     <a data-toggle="collapse" href="#collapse1">TypeError</a>
                   </h4>
                 </div>
                 <div id="collapse1" class="panel-collapse collapse">
                   <div class="panel-body">Error details</div>
                 </div>
               </div>
             </div>*/
            var $panel = $('<div>')
                .addClass('content ui-widget')
                .appendTo($div);
            var $header = $('<div>')
                .addClass('ui-widget-header')
                .text(text)
                .appendTo($panel);
            // Collapse long backtrace.
            if (data.backtrace) {
                $panel.addClass('collapsible-panel');
                var $content = $('<div>')
                    .addClass('ui-widget-content backtrace')
                    .appendTo($panel)
                    .addClass('collapsed')
                    .hide();
                $.each(data.backtrace, function (index, trace) {
                    // TODO: make file paths links to open in editor with line number; if file exists (open successful)
                    // switch to editor.
                    var fullpath = trace.replace(/\:\d+(?:\:.+)?$/, ''); // Removes the line number suffix.
                    var $trace = $('<div>')
                        .attr('title', fullpath)
                        .text( (data.backtrace_short) ? data.backtrace_short[index] : trace )
                        .appendTo($content);
                });
                var collapsed = true;
                $header.on('click', function () {
                    if (collapsed) {
                        $content.show();
                        $panel.removeClass('collapsed');
                    } else {
                        $content.hide();
                        $panel.addClass('collapsed');
                    }
                    collapsed = !collapsed;
                });
            }
            $previousMessage = $div;
            $div.data('text', data.text); // Save original text as attribute.
        } else { // if (/puts|print/.test(metadata.type))
            $code = $('<code>')
                .addClass('content selectable')
                .appendTo($div);
            // previousEntry = code; // TODO
            $previousMessage = $div;
            $div.data('text', data.text); // Save original text as attribute.
            //var originalText = data.text;
            //var xmlText = data.text.replace(/\</g, '&lt;').replace(/\>/g, '&gt;');
            //trigger('beforexmladded', data);
            //if (data.text == xmlText) {
            //    $code.text(originalText);
            //} else {
                $code.html(data.text);
                trigger('afterCodeAdded', $code, data);

            //}
        }

        // Add counter to combine repeated entries.
        if (/puts|print|error|warn/.test(data.type)) { // TODO ////////////////////////////
            var $counter = $('<div>')
                .addClass('counter')
                .appendTo($div)
                .hide();
            var count = 1;
            $div.data('increaseCounter', function () {
                $counter.show();
                count++;
                $counter.text(count);
            });
        }

        // Add time stamp.
        var $timestamp = $('<div>')
            .addClass('time')
            .text(formatTime(data.time))
            .appendTo($div);

        $outputElement.append($div);

        // Hook for div added to output.
        trigger('added', $div[0], text, data);
    };


    // Metadata contains time in seconds, and JavaScript uses milliseconds.
    function formatTime (time) {
        var d = (time instanceof Date) ? time : (typeof time === 'number') ? new Date(time * 1000) : new Date;
        return stringRjust(d.getHours(),        2, '0') + ':' +
            stringRjust(d.getMinutes(),      2, '0') + ':' +
            stringRjust(d.getSeconds(),      2, '0') + '.' +
            stringRjust(d.getMilliseconds(), 3, '0');
    }


    /**
     * Repeat a string a given number of times.
     * @param   {string} string
     * @param   {number} times   an integer
     * @returns {string} the modified string
     */
    function stringRepeat (string, times) {
        var newString = '';
        for (var i = 0; i < times; i++) {
            newString += string;
        }
        return newString;
    }


    /**
     * Fill up a string to a new width so that the original string is aligned at the right.
     * @param   {string}  string
     * @param   {number}  width     an integer
     * @param   {string} [padding]  a single character to be used as padding, defaults to a whitespace.
     * @returns {string} the modified string
     */
    function stringRjust (string, width, padding) {
        if (typeof string !== 'string') string = String(string);
        padding = padding || ' ';
        padding = padding.substr(0, 1);
        if (string.length < width) {
            return stringRepeat(padding, width - string.length) + string;
        } else {
            return string;
        }
    }


    initialize();
};