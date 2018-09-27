define(['jquery', 'bootstrap'], function ($, _) {
    return function (element, settings) {

        var output = this,
            $outputElement = $(element),
            nextMessageNewEntry = true,
            $previousEntryElement = null,
            previousText = null,
            lineNumber = 1;

        function initialize () {
            settings.getProperty('useWrapMode').bindAction('change', function (value) {
                $outputElement.toggleClass('wrap_lines', value);
            });
            // Set the font family from settings (uses default if null or "").
            settings.getProperty('font_family').bindAction('change', function (value) {
                $outputElement.css('font-family', value);
            });
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
            // Ensure metadata is complete, make a copy for internal use.
            metadata = $.extend({}, metadata); // Supports metadata argument not given (undefined).
            metadata.type = metadata.type || 'other';
            
            // Identical messages: Skip but increase the counter.
            if (!/input|result/.test(metadata.type) && 
                    nextMessageNewEntry && 
                    text !== '\n' &&
                    text === previousText &&
                    $previousEntryElement) {
                increaseCounter($previousEntryElement);
                return;
            }

            // Empty line after puts/warn: Skip and remember to put next message on new entry.
            //
            // Unfortunately SketchUp's stdout and stderr have only one `write` method
            // that prints inline text. To produce new lines (like with `puts`), it sends
            // a single line break afterwards. In that case we receive a `print` with '\n'
            // and later a `print` with the next message (puts or error).
            // So we absorb the line break and let the next message start in a new line.
            if (text === '\n' && /print|error|warn/.test(metadata.type)) {
                // This case actually means "puts follows" or "error follows"
                nextMessageNewEntry = true;
                return;
            }

            // Real print: attach to previous row.
            if (/print/.test(metadata.type) && !nextMessageNewEntry) {
                if (nextMessageNewEntry) {
                    // Previous message required a new row (input, result, error)
                    createNewEntry(text, metadata);
                    previousText = text;
                } else {
                    attachToPreviousEntry(text);
                    previousText += text;
                }
                nextMessageNewEntry = false;
            } else {
                // input, result, puts, warn, error
                createNewEntry(text, metadata);
                previousText = text;
                nextMessageNewEntry = true;
            }
        };

        /**
         * Clears the output.
         */
        this.clear = function () {
            $outputElement.empty();
            nextMessageNewEntry = true;
            $previousEntryElement = null;
            previousText = null;
        };

        /**
         * Insert text to the previous entry.
         * @param {string} text
         * @private
         */
        var attachToPreviousEntry = function (text) {
            $previousEntryElement.append(text);
            // Add line number
            $('.gutter', $previousEntryElement).append(
                $('<div>').text(lineNumber++).addClass('ace_gutter-cell unselectable')
            );
        };

        /**
         * Creates a new entry.
         * @param {string} text
         * @param {object=} data
         * @private
         */
        var createNewEntry = function (text, data) {
            if (typeof text !== 'string') return;
            data.text = text;

            var $entryElement = $('<div>')
            .addClass('message')
            .addClass(data.type)
            //.addClass('ace_scroller ace_text-layer'); // Tweaks for ace. // TODO: Verify that ace_scroller is not
            // needed, it causes ugly drop shadow in ambiance theme.
            .addClass('ace_text-layer'); // Tweaks for ace.

            // Add gutter on the left side to continue the editor's gutter and for message type icons.
            var $gutter = $('<div>')
            .addClass('gutter')
            .addClass('ace_gutter ace_layer ace_gutter-layer ace_folding-enabled'); // Tweaks to style it like ace.
            $entryElement.append($gutter);
            // Add line numbers
            if (/input/.test(data.type)) {
                var lineNumber = data.line_number || 1;
                var lineEnd = lineNumber + text.split(/\r\n|\r|\n/).length;
                for (; lineNumber <= lineEnd; lineNumber++) {
                    $gutter.append(
                        $('<div>').addClass('ace_gutter-cell unselectable').attr('data-text', lineNumber)
                    );
                }
            }

            // Hook for raw text.
            trigger('beforeadded', data);

            // Input / result as highlighted code.
            if (/input|result/.test(data.type)) {
                addCode($entryElement, data);

            // Error details.
            } else if (/error|warn/.test(data.type)) {
                addError($entryElement, data);
                // TODO: if error was in console input, find the input entryElement and highlight the error.

            // Puts / print as text.
            } else { // if (/puts|print/.test(metadata.type))
                addText($entryElement, data);
            }

            // Add counter to combine repeated entries.
            if (!/input|result/.test(data.type)) {
                addCounter($entryElement);
            }

            // Add time stamp.
            addTimeStamp($entryElement, data.time);

            $outputElement.append($entryElement);
            // Hook for div added to output.
            trigger('added', $entryElement[0], text, data);
            $previousEntryElement = $entryElement;
        };

        function addCounter ($entryElement) {
            $('<div>')
            .addClass('counter unselectable')
            .appendTo($entryElement)
            .hide();
        }

        function increaseCounter ($entryElement) {
            var $counter = $entryElement.find('.counter').show();
            var count = parseInt($counter.attr('data-text')) || 1;
            $counter.attr('data-text', count + 1);
        }

        function addTimeStamp ($entryElement, time) {
            $('<div>')
            .addClass('time unselectable')
            .attr('data-text', formatTime(time))
            .appendTo($entryElement);
        }

        function addCode ($entryElement, data) {
            if (typeof output.highlight !== 'function')
                return addText($entryElement, data);
            data.html = output.highlight(data.text);
            $('<code>')
            .addClass('content')
            .html(data.html)
            .appendTo($entryElement);
        }

        function addText ($entryElement, data) {
            $('<code>')
            .addClass('content')
            .text(data.text)
            .appendTo($entryElement);
        }

        function addError ($entryElement, data) {
            var $panel = $('<div>')
            .addClass('content')
            .appendTo($entryElement);

            var $header = $('<div>')
            .text(data.text)
            .addClass('header')
            .appendTo($panel);

            if (data.backtrace && data.backtrace.length > 0) {
                var $content = $('<div>')
                .addClass('backtrace')
                .addClass('collapse')
                .collapse({toggle: false})
                .appendTo($panel);
                $header.on('click', function () {  $(this).next().collapse('toggle'); });

                // Collapse long backtrace.
                $.each(data.backtrace, function (index, trace) {
                    var $trace = $('<div>');
                    //var match = trace.match(/^(.+[\/\\].+)\:(\d+)(?:\:.+)?$/);
                    var match = trace.match(/(?:file\:\/\/\/)?((?:\w\:[\\\/]|\/)[^\:]+)\:(\d+)(?:\:(\d+))?/);
                    if (match) {
                        var fullpath = match[1];
                        var lineNumber = parseInt(match[2]);
                        var columnNumber = parseInt(match[3]);
                        $trace.attr('title', fullpath)
                        .data('path', fullpath)
                        .data('line-number', lineNumber)
                        .data('column-number', columnNumber);
                        if (data.backtrace_short) trace = data.backtrace_short[index];
                    }
                    $trace.text(trace)
                    .appendTo($content);
                });
            }
        }

        // Format the time as a string (not including the date).
        // @overload formatTime(date)
        //   @param date {Date} a date object
        //   @returns {string}
        // @overload formatTime(time)
        //   @param time {number} time in seconds
        //   @returns {string}
        function formatTime (time) {
            var d = (time instanceof Date) ? time : 
                    (typeof time === 'number') ? new Date(time * 1000) : // JavaScript Date takes milliseconds
                    new Date();
            return stringRjust(d.getHours(),     2, '0') + ':' +
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
});
