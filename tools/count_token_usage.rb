#!/usr/bin/env ruby
# This script reads ruby files, searches expressions and tries to resolve the docpath. If successful, the docpath is counted in the ApiUsageCounter.

module AE

  module ConsolePlugin

    PATH = File.expand_path('../src/ae_console/') unless defined?(self::PATH)

    require_relative '../src/ae_console/features/tokenresolver.rb'
    require_relative '../src/ae_console/features/api_usage_counter.rb'

    module CountTokenUsage

      BUILTIN_CONSTANTS = [:Object, :Module, :Class, :BasicObject, :Kernel, :NilClass, :NIL, :Data, :TrueClass, :TRUE, :FalseClass, :FALSE, :Encoding, :Comparable, :Enumerable, :String, :Symbol, :Exception, :SystemExit, :SignalException, :Interrupt, :StandardError, :TypeError, :ArgumentError, :IndexError, :KeyError, :RangeError, :ScriptError, :SyntaxError, :LoadError, :NotImplementedError, :NameError, :NoMethodError, :RuntimeError, :SecurityError, :NoMemoryError, :EncodingError, :SystemCallError, :Errno, :UncaughtThrowError, :ZeroDivisionError, :FloatDomainError, :Numeric, :Integer, :Fixnum, :Float, :Bignum, :Array, :Hash, :ENV, :Struct, :RegexpError, :Regexp, :MatchData, :Marshal, :Range, :IOError, :EOFError, :IO, :STDIN, :STDOUT, :STDERR, :ARGF, :FileTest, :File, :Dir, :Time, :Random, :Signal, :Proc, :LocalJumpError, :SystemStackError, :Method, :UnboundMethod, :Binding, :Math, :GC, :ObjectSpace, :Enumerator, :StopIteration, :RubyVM, :Thread, :TOPLEVEL_BINDING, :ThreadGroup, :Mutex, :ThreadError, :Process, :Fiber, :FiberError, :Rational, :Complex, :RUBY_VERSION, :RUBY_RELEASE_DATE, :RUBY_PLATFORM, :RUBY_PATCHLEVEL, :RUBY_REVISION, :RUBY_DESCRIPTION, :RUBY_COPYRIGHT, :RUBY_ENGINE, :TracePoint, :ARGV, :Gem, :RbConfig, :CROSS_COMPILING, :ConditionVariable, :Queue, :SizedQueue, :MonitorMixin, :Monitor, :Sketchup, :SB_PROMPT, :SB_VCB_LABEL, :SB_VCB_VALUE, :Length, :Geom, :ORIGIN, :X_AXIS, :Y_AXIS, :Z_AXIS, :IDENTITY, :ORIGIN_2D, :X_AXIS_2D, :Y_AXIS_2D, :UI, :MB_OK, :MB_OKCANCEL, :MB_ABORTRETRYIGNORE, :MB_YESNOCANCEL, :MB_YESNO, :MB_RETRYCANCEL, :MB_MULTILINE, :VK_SPACE, :VK_PRIOR, :VK_NEXT, :VK_END, :VK_HOME, :VK_LEFT, :VK_UP, :VK_RIGHT, :VK_DOWN, :VK_INSERT, :VK_DELETE, :MF_ENABLED, :MF_GRAYED, :MF_DISABLED, :MF_CHECKED, :MF_UNCHECKED, :VK_SHIFT, :VK_CONTROL, :VK_ALT, :VK_COMMAND, :VK_MENU, :ALT_MODIFIER_KEY, :ALT_MODIFIER_MASK, :COPY_MODIFIER_KEY, :COPY_MODIFIER_MASK, :CONSTRAIN_MODIFIER_KEY, :CONSTRAIN_MODIFIER_MASK, :IDOK, :IDCANCEL, :IDABORT, :IDRETRY, :IDIGNORE, :IDYES, :IDNO, :SKETCHUP_CONSOLE, :TextAlignLeft, :TextAlignRight, :TextAlignCenter, :GL_POINTS, :GL_LINES, :GL_LINE_LOOP, :GL_LINE_STRIP, :GL_TRIANGLES, :GL_TRIANGLE_STRIP, :GL_TRIANGLE_FAN, :GL_QUADS, :GL_QUAD_STRIP, :GL_POLYGON, :MK_LBUTTON, :MK_RBUTTON, :MK_MBUTTON, :MK_SHIFT, :MK_CONTROL, :MK_ALT, :MK_COMMAND, :LAYER_VISIBLE_BY_DEFAULT, :LAYER_HIDDEN_BY_DEFAULT, :LAYER_USES_DEFAULT_VISIBILITY_ON_NEW_PAGES, :LAYER_IS_VISIBLE_ON_NEW_PAGES, :LAYER_IS_HIDDEN_ON_NEW_PAGES, :FILE_WRITE_OK, :FILE_WRITE_FAILED_INVALID_TYPE, :FILE_WRITE_FAILED_UNKNOWN, :SnapTo_Arbitrary, :SnapTo_Horizontal, :SnapTo_Vertical, :SnapTo_Sloped, :PAGE_USE_CAMERA, :PAGE_USE_RENDERING_OPTIONS, :PAGE_USE_SHADOWINFO, :PAGE_USE_SKETCHCS, :PAGE_USE_HIDDEN, :PAGE_USE_LAYER_VISIBILITY, :PAGE_USE_SECTION_PLANES, :PAGE_USE_ALL, :PAGE_NO_CAMERA, :DimensionArrowNone, :DimensionArrowSlash, :DimensionArrowDot, :DimensionArrowClosed, :DimensionArrowOpen, :ALeaderNone, :ALeaderView, :ALeaderModel, :Test, :TB_HIDDEN, :TB_VISIBLE, :TB_NEVER_SHOWN, :CMD_SELECT, :CMD_PAINT, :CMD_ERASE, :CMD_RECTANGLE, :CMD_LINE, :CMD_CIRCLE, :CMD_ARC, :CMD_POLYGON, :CMD_FREEHAND, :CMD_PUSHPULL, :CMD_TEXT, :CMD_MOVE, :CMD_ROTATE, :CMD_EXTRUDE, :CMD_SCALE, :CMD_OFFSET, :CMD_MEASURE, :CMD_PROTRACTOR, :CMD_SKETCHCS, :CMD_SECTION, :CMD_DRAWOUTLINES, :CMD_DRAWCUTS, :CMD_ORBIT, :CMD_DOLLY, :CMD_ZOOM, :CMD_ZOOM_WINDOW, :CMD_ZOOM_EXTENTS, :CMD_CAMERA_UNDO, :CMD_WIREFRAME, :CMD_HIDDENLINE, :CMD_SHADED, :CMD_TEXTURED, :CMD_TRANSPARENT, :CMD_WALK, :CMD_PAN, :CMD_MAKE_COMPONENT, :CMD_DIMENSION, :CMD_VIEW_ISO, :CMD_VIEW_TOP, :CMD_VIEW_FRONT, :CMD_VIEW_RIGHT, :CMD_VIEW_BACK, :CMD_VIEW_LEFT, :CMD_VIEW_BOTTOM, :CMD_VIEW_PERSPECTIVE, :CMD_POSITION_CAMERA, :CMD_NEW, :CMD_OPEN, :CMD_SAVE, :CMD_CUT, :CMD_COPY, :CMD_PASTE, :CMD_DELETE, :CMD_UNDO, :CMD_REDO, :CMD_PRINT, :CMD_PAGE_NEW, :CMD_PAGE_DELETE, :CMD_PAGE_UPDATE, :CMD_PAGE_NEXT, :CMD_PAGE_PREVIOUS, :CMD_RUBY_CONSOLE, :CMD_SKETCHAXES, :CMD_SHOWHIDDEN, :CMD_SHOWGUIDES, :CMD_SELECTION_ZOOM_EXT, :CMD_DISPLAY_FOV, :SKSocket, :Layout, :IDENTITY_2D, :SketchupExtension, :LanguageHandler, :RUBYGEMS_ACTIVATION_MONITOR]

      class << self

        def find_files(root='.')
          return Dir.glob(File.join(root, '**', '*.rb'))
        end

        def read_file(filepath)
          File.open(filepath, 'r') { |f|
            return f.read()
          }
        end

        def find_expressions(string)
          return string.scan(/(?:[\w_@]@?[\w\d_]*[!?]?|[*+-\/%][=]?)(?:(?:\.|\:\:)(?:[\w_][\w\d_]*[!?]?|[*+-\/%][=]?))*/)
        end

        def resolve_expression(expression_string)
          tokens = expression_string.split(/\.|::/)
          classification = TokenResolver.resolve_tokens(tokens)
          return classification
        end

        def main(input_dir='.')
          data_path = File.join(PATH, 'data') # "../src/ae_console/data"
          Dir.mkdir(data_path) unless File.exist?(data_path)
          data_file = File.join(data_path, 'generated_api_usage_statistics.json')
          counter = ApiUsageCounter.new(data_file)
          find_files(input_dir).each{ |script_path|
            begin
              find_expressions(read_file(script_path)).each{ |expression|
                tokens = expression.split(/\.|::/)
                # Count single tokens, root classes/modules
                if tokens.length == 1 && BUILTIN_CONSTANTS.include?(tokens.first.to_s.to_sym)
                  counter.used(tokens.first.to_s)
                  next
                end
                # Count type-inferred tokens (min length 2 for meaningful inference)
                next if tokens.length < 2
                (2..tokens.length).each{ |l|
                  begin
                    classification = TokenResolver.resolve_tokens(tokens[0...l])
                    # Ignore MultipleTokenClassification because it is ambiguous
                    next if classification.is_a?(MultipleTokenClassification)
                    # Count only types of classes/modules shipped by SketchUp, not from my extensions.
                    next unless BUILTIN_CONSTANTS.include?(classification.docpath.split(/\.|::/).first.to_sym)
                    counter.used(classification.docpath)
                  rescue TokenResolver::TokenResolverError => e
                  end
                }
              }
            rescue Exception => e
            end
          }
          counter.save
          nil
        end

      end

      #self.main(*ARGV)

    end

  end

end
