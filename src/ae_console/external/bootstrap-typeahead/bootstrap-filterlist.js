(function (factory) {
    if (typeof define === 'function' && define.amd) {
        // AMD. Register as an anonymous module.
        define(['jquery', 'bootstrap-typeahead'], factory);
    } else if (typeof exports === 'object') {
        // Node/CommonJS
        factory(require('jquery'));
    } else {
        // Browser globals
        factory(jQuery);
    }
}(function($) {
    $.fn.filterlist = function(options) {
        options = $.extend({}, $.fn.filterlist.defaults, options)
        
        this.typeahead(options);

        var typeahead = this.data('typeahead');

        // Instead of hiding the list, show default data.
        typeahead.hide = function () {
            //this.reset();
        };
        
        typeahead.empty = function () {
            // Empty the list.
            this.$menu.empty().append(this.options.noResultsText);
        };

        // Reset the search results and show the defaultData.
        typeahead.reset = function () {
            var items = $.isFunction(this.options.defaultData) ? this.options.defaultData() : this.options.defaultData;
            if (items) this.render(items.slice(0, this.options.items));
            return this;
        };

        typeahead.lookup = function (event) {
            this.query = this.$element.val();
            // When query is empty or too short, switch to defaultData view.
            if (!this.query || this.query.length < this.options.minLength) {
                this.reset();
                return this;
            }
            // Otherwise process the query and show results or fallback for no results.
            if ($.isFunction(this.source)) {
                var that = this;
                this.source(this.query, function (items) {
                    (items.length > 0) ? that.process(items) : that.empty();
                });
            } else {
                (this.source && this.source.length > 0) ? this.process(this.source) : this.empty();
            }
            return this;
        };

        // Use an optional renderer function to generate html for an item.
        typeahead.render = function (items) {
            var that = this;
            items = $(items).map(function (i, item) {
                i = $(that.options.renderer(item, that.query)).attr('data-value', item).attr('title', item);
                return i[0];
            });
            items.first().addClass('active');
            this.$menu.html(items);
            return this;
        }

        // Improved sorter: consider number of occurences of the pattern.
        typeahead.sorter = function (items) {
            var numberMatches,
                manyMatches = [],
                twoMatches = [],
                beginswith = [],
                caseSensitive = [],
                caseInsensitive = [],
                item;

            while (item = items.shift()) {
                numberMatches = (item.match(new RegExp(this.query, 'ig')) || []).length;
                if (numberMatches > 2) {
                    manyMatches.push(item);
                } else if (numberMatches > 1) {
                    twoMatches.push(item);
                } else if (!item.toLowerCase().indexOf(this.query.toLowerCase())) {
                    beginswith.push(item);
                } else if (~item.indexOf(this.query)) {
                    caseSensitive.push(item);
                } else {
                    caseInsensitive.push(item);
                }
            }
            return manyMatches.concat(twoMatches, beginswith, caseSensitive, caseInsensitive);
        };

        this.data('typeahead').lookup();
        return this;
    };
    
    $.fn.filterlist.defaults = {
        // Initial view for empty input (list of items or function that returns items)
        initialData: [],
        // View when no data matched input.
        noResultsText: '',
        // Renders an item as html.
        renderer: function (item) {
            return $('<li>').append($('<a href="#">').text(item));
        },
        submit: function () {}
    };
}));
