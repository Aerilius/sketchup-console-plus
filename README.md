# Ruby Console+

This is an extendible Ruby Console using the powerful ace code editor with code highlighting, indentation, code folding… It lets you open multiple independent instances of the console and remembers the command history over sessions.

<p align="center"><img alt="logo" src="./src/ae_console/images/icon_128.png" /></p>

## Requirements

- **SketchUp 2017**
  This extension has been completely rebuilt to take advantage of modern technologies (the new HtmlDialog with modern JavaScript support, Ruby 2.0).

## Installation

- Go to the releases page (↑) and download the latest .rbz file. Open in SketchUp _Window → Extension Manager_ and select the .rbz file.

- Alternatively, you can install the contents of the `src` directory into your plugins folder.

## Usage

(Menu) `Window → Ruby Console+`

There are two modes:

- <img alt="Console" src="./src/ae_console/images/console.png" align="left" width="24" /> The console is a command line interface to try out codes and inspect return values. With the <kbd>Enter</kbd> key, code will be evaluated (use shift-enter for line breaks).

- <img alt="Editor" src="./src/ae_console/images/editor.png" align="left" width="24" /> The editor is a full-featured text file editor. Here you turn code into a script and save it. 

### Features

- **Autocompletion** and **doc tooltips**: Intelligent live autocompletion tells you not only which methods you can call next on a reference but provides you also with detailed info on how to use correctly use them.

- **Entity inspection**: Hover an entity or point in the console output and you will see it highlighted in the model.

- <img alt="Select" src="./src/ae_console/images/select.png" align="left" width="24" /> Get a **reference to an entity** in the model by picking it with the pointer. (No more selecting and `Sketchup.active_model.selection[0]`.)
  By holding the ctrl key when the main window is focussed, you can select points and by holding the shift key you can turn on inferencing.

- Remembers which scripts you reload and **reloads scripts** automatically whenever they are changed.

- <img alt="Clear" src="./src/ae_console/images/clear.png" align="left" width="24" /> Clear the console

- <img alt="Help" src="./src/ae_console/images/help.png" align="left" width="24" /> Opens online **documentation** for the currently focused word (beta)

- <img alt="Menu" src="./src/ae_console/images/menu.png" align="left" width="24" /> Menu with preferences

- **Binding**: An advanced feature that allows to step into an object or class and call method or instance variable as if you were locally inside of that class. Try to set binding to `Math` and you can directly call math functions like `sqrt` without NameError.

## License

MIT License (MIT)

