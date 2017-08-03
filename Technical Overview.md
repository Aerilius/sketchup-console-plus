# Technical Overview

This third version of the Ruby Console+ makes use of the observer pattern, asynchronous communication and promises.

## Ace Editor

The [ace editor](https://ace.c9.io/) is an IDE based on web technologies.
To update to a new version, download from the [prepackaged versions](https://github.com/ajaxorg/ace-builds/). For the old Internet-Explorer-based webdialogs in older SketchUp versions, I had to heavily patch ace to circumvent errors caused by limited web standard support. This is no necessary anymore since this version does at the moment not aim for backward compatibility. Remaining patches can be found in the `patches` directory. 

## Bridge

The Bridge class had originally been created because SketchUp's WebDialog used to have severe limitations for communicating between the Ruby interpreter and JavaScript (unicode, message length, serialization, message loss). The move to HtmlDialog solved most issues, so now it is mostly used for convenience for its a powerful API. 

Communication is completely asynchronous and based on **promises**. A promise is a proxy object for the result of an operation (that may be asynchronous). Subsequent operations can be scheduled immediately on the promise and will be executed as soon as the result is available. 

## Features System

To handle the growing amount of features, they are implemented like extensions, with the core console having only elementary functionality. A feature can bring both Ruby code and JavaScript code.

The plugin searches features in the features folder and loads them as soon as the plugin is loaded, and loads JavaScript whenever a console dialog is opened. A feature is initialized with a struct giving access to several components of the plugin (consoles) on which it can listen for events and act on them (console dialog opened etc.). 

## JavaScript Modules

Like the ace editor, the console now uses AMD modules. Requirejs loads a module definition after all dependent modules have been loaded asynchronously. If a function needs a module, it can require its dependencies as in an array and than access them as parameters of a callback function:

    requirejs(['module_name'], function callback (module) {});

The `main` module configures paths where to look up modules and then loads the user interface controller in `app`.

## User Interface

The user interface uses Bootstrap for CSS and some widgets. The user interface consists of modules `console` (with `output`) and `editor`, which each are wrappers around an instance of ace.
