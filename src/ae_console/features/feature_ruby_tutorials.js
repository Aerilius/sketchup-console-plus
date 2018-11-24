requirejs(['app', 'bridge', 'translate', 'menu', 'ace/ace'], function (app, Bridge, Translate, Menu, ace) {

    ace.require('ace/lib/dom').importCssString("\
.ruby_tutorials_toolbar {                 \
    float: right;                         \
    position: relative;                   \
    z-index: 1;                           \
}                                         \
.ruby_tutorials_toolbar:after {           \
    content: '';                          \
    clear: both;                          \
}                                         \
.ruby_tutorials_toolbar button {          \
    width: 1.5em;                         \
    height: 1.5em;                        \
    text-align: center;                   \
    cursor: pointer;                      \
}                                         \
.ruby_tutorials_toolbar button img {      \
    vertical-align: middle;               \
    width: 1em;                           \
    height: 1em;                          \
}                                         \
.ruby_tutorials_toolbar button[disabled] {\
    cursor: default;                      \
}                                         \
.ruby_tutorials_toolbar button[disabled] img {\
    opacity: 0.5;                         \
}                                         \
");

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
        app.console.setContent(text);
        var editor = app.console.aceEditor;
        editor.navigateFileEnd();
        editor.navigateLineEnd();
        editor.container.scrollIntoView();
    }

    function evaluateInConsole (text) {
        app.console.submit(text);
    }

    function waitForMessage (id) {
        if (document.getElementById('message_id_' + id) != null) {
            return Promise.resolve(true);
        } else {
            return new Promise(function (resolve, reject) {
                var waitFunction;
                waitFunction = function (event, args) {
                    var data = args[2];
                    if (data.id == id) {
                        $(app.output).off('added', waitFunction);
                        resolve(true);
                    }
                }
                $(app.output).on('added', waitFunction);
            });
        }
    }

    function addHtmlToOutput (html) {
        var insertCodeOnDblClick = function (event, args) {
            var element = args[0];
            $('pre code', element).click(function () {
                var codeElement = $(this).get(0);
                var code = codeElement.innerText;
                insertInConsoleEditor(code);
                app.console.focus();
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

    // Publish methods so that they can be accessed from Ruby side of this feature (FIXME: not very elegant, avoid clashes).
    window.insertInConsoleEditor = insertInConsoleEditor;
    window.addHtmlToOutput = addHtmlToOutput;
    window.waitForMessage = waitForMessage;
    window.evaluateInConsole = evaluateInConsole;
});
