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
    app.consoleMenu.addItem(Translate.get('tutorials'), function () {
        //Bridge.call('show_tutorial_selector');
        showTutorialSelector();
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

    function showTutorialSelector () {
        Promise.all([Bridge.get('get_tutorials'), Bridge.get('get_next_tutorial_and_step')]).then(function (results) {
            var tutorials = results[0],
                nextTutorial = results[1][0],
                nextStep = results[1][1];
            var html = '<div>' +
                '  <label>' + Translate.get('Select a tutorial') + 
                '    <select id="ruby_tutorials_input_next_tutorial" value="' + nextTutorial + '">';
            for (var i = 0; i < tutorials.length; i++) {
                html += '      <option value="' + tutorials[i].filepath + '"';
                if (tutorials[i].filepath == nextTutorial) html += 'selected';
                html += '>' + tutorials[i].display_name + '</option>';
            }
            html += '    </select>' +
                '  </label>' +
                '  <label>' + Translate.get('Step') + 
                '    <input id="ruby_tutorials_input_next_step" type="number" value="' + nextStep + '" />' + 
                '  </label>' +
                '  <button onclick="Bridge.call(\'start_tutorial\', $(\'#ruby_tutorials_input_next_tutorial\').val(), parseInt($(\'#ruby_tutorials_input_next_step\').val()))">' + Translate.get('Start') + 
                '  </button>' +
                '</div>';
            addHtmlToOutput(html);
        })
    }

    function addHtmlToOutput (html) {
        var insertCodeOnDblClick = function (event, args) {
            var element = args[0];
            $('pre code', element).addClass('ace_editor').click(function () {
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

    // Publish methods so that they can be accessed from Ruby side of this feature
    window.FeatureRubyTutorials = {
        insertInConsoleEditor: insertInConsoleEditor,
        addHtmlToOutput: addHtmlToOutput,
        waitForMessage: waitForMessage,
        evaluateInConsole: evaluateInConsole,
        showTutorialSelector: showTutorialSelector
    };
});
