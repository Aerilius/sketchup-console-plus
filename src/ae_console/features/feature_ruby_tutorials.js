requirejs(['app', 'bridge', 'translate', 'menu'], function (app, Bridge, Translate, Menu) {

    // Submenu for tutorials.
    var tutorialsMenu = new Menu('<ul id="tutorials_dropdown" class="dropdown-menu menu" style="top: 0; left: -10em; width: 10em; min-height: 28em;">'); /* Workaround for missing submenu positioning: min-height */
    app.consoleMenu.addSubmenu(tutorialsMenu, Translate.get('tutorials'));

    Bridge.get('get_tutorials').then(function (tutorialData) {
        for (var i = 0; i < tutorialData.length; i++) {
            var tutorialItem = tutorialData[i];
            tutorialsMenu.addItem(tutorialItem.display_name, function () {
                Bridge.call('start_tutorial', tutorialItem.filename)
            });
        }
    });

    function insertInConsoleEditor (text) {
        var editor = app.console.aceEditor;
        editor.setValue(text);
        editor.navigateFileEnd();
        editor.navigateLineEnd();
        editor.container.scrollIntoView();
    }
    
    function addHtmlToOutput (html) {
        var insertCodeOnDblClick = function (event, args) {
            var element = args[0];
            $('pre code', element).click(function () {
                var codeElement = $(this).get(0);
                var code = codeElement.innerText;
                insertInConsoleEditor(code);
                app.console.aceEditor.focus();
            }).hover(function () {
              $(this).css('cursor', 'pointer');
            }, function () {
              $(this).css('cursor', null);
            });
        };
        $(app.output).one('added', insertCodeOnDblClick);
        app.output.add(html, { type: 'puts html'});
        app.console.aceEditor.container.scrollIntoView();
    }

    function addMarkDownToOutput (markdown) {
        
    }

    // Publish methods so that they can be accessed from Ruby side of this feature (FIXME: not very elegant, avoid clashes).
    window.insertInConsoleEditor = insertInConsoleEditor;
    window.addHtmlToOutput = addHtmlToOutput;
});
