requirejs(['app', 'bridge', 'translate', 'menu'], function (app, Bridge, Translate, Menu) {
    var autoReloadFiles = app.settings.getProperty('reload_scripts', []);
    
    // Submenu for auto reload feature.
    var autoReloadMenu = new Menu('<ul id="reload_scripts_dropdown" class="dropdown-menu menu" style="top: 0; left: -25em; width: 25em; min-height: 12em;">'); /* Workaround for missing submenu positioning: min-height */
    app.consoleMenu.addSubmenu(autoReloadMenu, 'reload_scripts');

    function buildAutoReloadMenuItems (filepaths) {
        $(autoReloadMenu.element).empty();
        autoReloadMenu.addItem($('<b>')
        .text(Translate.get('Click to remove files from auto-loading')));
        $.each(filepaths, function(i, filepath){
            autoReloadMenu.addItem(filepath, function (event) {
                event.stopPropagation();
                autoReloadMenu.removeItem(filepath);
                // Remove it from settings.
                var fs = app.settings.get('reload_scripts');
                fs.splice(fs.indexOf(filepath), 1);
                app.settings.set('reload_scripts', fs);
                // Stop observing the file.
                Bridge.call('stop_observing_file', filepath);
            });
        });
    }
    buildAutoReloadMenuItems(autoReloadFiles.getValue());
    autoReloadFiles.addListener('change', buildAutoReloadMenuItems);

    var tmpID = null; // Cache the id of the last input so it can be matched to its result.
    var tmpPath = '';

    app.console.addListener('input', function (text, metadata) {
        if (/\bload[\(|\s][\"\']([^\"\']+)[\"\']\)?/.test(text)) {
            tmpID = metadata.id;
            tmpPath = RegExp.$1;
        } else {
            tmpID = null;
        }
    });

    // If the script was loaded successfully, then add it to the menu.
    app.console.addListener('result', function (text, metadata) {
        if (tmpID == metadata.source && tmpPath !== '') {
            // If the file is not yet observed.
            var fs = app.settings.get('reload_scripts');
            if (fs.indexOf(tmpPath) == -1) {
                fs.push(tmpPath);
                app.settings.getProperty('reload_scripts').setValue(fs);
                Bridge.call('start_observing_file', tmpPath);
            }
        }
    });

    app.console.addListener('error', function (text, metadata) {
        // If the previous input attempted to load a file, it failed.
        tmpID = null;
    });
});
