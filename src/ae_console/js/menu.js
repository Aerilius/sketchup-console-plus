define(['jquery', 'bootstrap', './translate'], function ($, _, Translate) {
    return function (element) {

        var $menuElement = $(element||'<ul>');
        var $menuItems = {};
        this.element = $menuElement[0];

        /**
         * Add an arbitrary item to the menu.
         * @overload
         *   @param item {HTMLElement, string, jQuery} - The html to add for this item.
         *   @param name {string}                      - A short identifier to access this item again.
         *   @param onClickedCallback {function}       - An optional callback when the item is clicked.
         * @overload
         *   @param item {HTMLElement, string, jQuery} - The html to add for this item.
         *   @param onClickedCallback {function}       - An optional callback when the item is clicked.
         * @returns {Menu}
         */
        this.addItem = function (item, name, onClickedCallback) {
            if (!(item && item.jquery || typeof item === 'string' || item instanceof HTMLElement)) { throw TypeError('addItem must be called with an HTML element or HTML string'); };
            if (typeof name === 'function') {
                onClickedCallback = name;
                name = item;
                item = Translate.get(name);
            }
            var $li;
            $li = $('<li>').append(item);
            $menuElement.append($li);
            $menuItems[name||item] = $li;
            if (typeof onClickedCallback === 'function') $li.on('click', onClickedCallback);
            return this;
        };

        this.removeItem = function (name) {
            $menuItems[name] && $menuItems[name].remove();
            return this;
        };

        this.addSeparator = function () {
            $menuElement.append('<hr>');
            return this;
        };

        this.addSubmenu = function (menu, name, onClickedCallback) {
            if (!(menu && menu.constructor === this.constructor)) { throw TypeError('addSubmenu must be called with a Menu'); };
            if (typeof name === 'function') { onClickedCallback = name; name = menu; }
            var $li;
            $li = $('<li>').text(Translate.get(name)).append(menu.element);
            $li.attr('data-toggle', 'dropdown').dropdown()
            .on('mouseover', function(event){
                $(menu.element).toggle(true);
            }).on('mouseout', function(event) {
                $(menu.element).toggle(false);
            });
            // Workaround: click on item that has submenu closes bootstrap parent menu.
            $li.off('click');
            $li.on('click', function (event) {
                event.stopPropagation();
            });
            $menuElement.append($li);
            $menuItems[name] = $li;
            
            return this;
        };

        this.addProperty = function (property) {
            var $input, $li,
                name = property.getName(),
                value = property.getValue();
            if (typeof value === 'number') {
                // Number input
                $input = $('<input type="number">').val(value);
            } else if (typeof value === 'string') {
                // Text input
                $input = $('<input type="text">').val(value);
            } else if (typeof value === 'boolean') {
                // Checkbox
                $input = $('<input type="checkbox">').prop('checked', value);
            } else {
                throw TypeError('unsupported property type '+(typeof value)+' of '+JSON.stringify(value));
            }
            $input.attr('name', name);
            // Bind the property with the input.
            property.bindAction('change', function(newValue) {
                // This programmatical change of the input's value does not trigger the input's change event.
                if (typeof value === 'boolean') {
                    $input.prop('checked', newValue);
                } else {
                    $input.val(newValue);
                }
            });
            $input.on('change', function () {
                if (typeof value === 'number') {
                    property.setValue(Number($input.val()));
                } else if (typeof value === 'boolean') {
                    property.setValue($input.prop('checked'));
                } else {
                    property.setValue($input.val());
                }
            });
            // Add a label and the input to the menu.
            $li = $('<li>').append(
                $('<label>').text(Translate.get(name)).append($input)
            );
            $li.on('click', function (event) {
                event.stopPropagation();
            });
            $menuElement.append($li);
            $menuItems[name] = $li;
            return this;
        };

        this.addAlternativesProperty = function (property, alternatives, alternativesDisplayNames) {
            var $input, $li,
                name = property.getName();
            if (!alternativesDisplayNames) alternativesDisplayNames = alternatives;
            // Create a select input.
            $input = $('<select>');
            for (var i = 0; i < alternatives.length; i++) {
                $input.append(
                    $('<option>')
                        .val(alternatives[i])
                        .text(Translate.get(alternativesDisplayNames[i]))
                );
            }
            $input.attr('name', name);
            // Bind the property with the input (this also sets the initial value).
            property.bindAction('change', function(newValue) {
                // This programmatical change of the input's value does not trigger the input's change event.
                $input.val(newValue);
            });
            $input.on('change', function () {
                property.setValue($input.val());
            });
            // Add a label and the input to the menu.
            $li = $('<li>').append(
                $('<label>').text(Translate.get(name)).append($input)
            );
            $li.on('click', function (event) {
                event.stopPropagation();
            });
            $menuElement.append($li);
            $menuItems[name] = $li;
            return this;
        };

    };
});
