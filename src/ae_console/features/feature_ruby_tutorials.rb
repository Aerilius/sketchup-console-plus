require 'json'
require 'uri'
require_relative '../bridge'

module AE

  module ConsolePlugin

    class FeatureRubyTutorials

      TRY_RUBY_FILENAME = 'try_ruby.json'

      def initialize(app)
        app.plugin.on(:console_added){ |console_instance|
          dialog = console_instance.dialog

          # Callback from webdialog menu
          dialog.on('get_tutorials') { |action_context|
            action_context.resolve(find_tutorials.map{ |tutorial_filename|
              {
                :filename => tutorial_filename,
                :display_name => self.class.to_title_case(File.basename(tutorial_filename, '.json'))
              }
            })
          }
          dialog.on('start_tutorial') { |action_context, tutorial_filename|
            self.class.start_tutorial(console_instance, tutorial_filename)
          }

        }
        # Start-up notification on first start.
        if app.settings[:first_start].nil?
          app.settings[:first_start] = true # TODO: false
          on_first_start
        end
      end

      def get_javascript_path
        return 'feature_ruby_tutorials.js'
      end

      def self.start_tutorial(console_instance, tutorial_filename, locale = Sketchup.get_locale)
        tutorial_path = File.join(PATH, 'Resources', locale, 'tutorials', tutorial_filename)
        tutorial_display_name = self.to_title_case(File.basename(tutorial_filename, '.json'))
        if File.exist?(tutorial_path)
          Tutorial.new(console_instance, tutorial_path, tutorial_display_name).start
        else
          fallback_tutorial_path = File.join(PATH, 'Resources', 'en-US', 'tutorials', tutorial_filename)
          Tutorial.new(console_instance, fallback_tutorial_path, tutorial_display_name).start
        end
      end

      def find_tutorials
        return Dir.glob(File.join(PATH, 'Resources', 'en-US', 'tutorials', '*.json')).map{ |tutorial_path|
          File.basename(tutorial_path)
        }
      end

      def self.to_title_case(string)
        string.split(/[\s_-]+/).map(&:capitalize).join(' ')
      end

      def on_first_start
        properties = {
            :dialog_title    => TRANSLATE['Welcome in Ruby Console+'],
            :scrollable      => false,
            :resizable       => true,
            :width           => 520,
            :height          => 240,
        }
        if defined?(UI::HtmlDialog)
          properties[:style] = UI::HtmlDialog::STYLE_DIALOG
          startup_dialog = UI::HtmlDialog.new(properties)
        else
          startup_dialog = UI::WebDialog.new(properties)
        end
        startup_dialog.set_file(File.join(PATH, 'html', 'startup_dialog.html'))

        # Add a Bridge to handle JavaScript-Ruby communication.
        bridge = Bridge.decorate(startup_dialog)

        startup_dialog.on('translate') { |action_context|
          # Translate.
          TRANSLATE.webdialog(startup_dialog)
        }
        startup_dialog.on('get_tutorials') { |action_context|
          # Get all SketchUp tutorials (exclude the basic Ruby tutorial since it is for the left button).
          action_context.resolve(find_tutorials.
          select{ |tutorial_filename| tutorial_filename != TRY_RUBY_FILENAME }.
          map{ |tutorial_filename|
            {
              :filename => tutorial_filename,
              :display_name => self.class.to_title_case(File.basename(tutorial_filename, '.json'))
            }
          })
        }
        startup_dialog.on('start_tryruby') { |action_context|
          self.class.open_console_with_tutorial(TRY_RUBY_FILENAME)
          startup_dialog.close
        }
        startup_dialog.on('start_tutorial') { |action_context, tutorial_filename|
          self.class.open_console_with_tutorial(tutorial_filename)
          startup_dialog.close
        }
        startup_dialog.on('close') { |action_context|
          startup_dialog.close()
        }

        startup_dialog.show
      end

      def self.open_console_with_tutorial(tutorial_filename)
        console_instance = ConsolePlugin.open
        console_instance.on(:shown) {
          # Wait until JavaScript is loaded.
          UI.start_timer(1, false) {
            self.start_tutorial(console_instance, tutorial_filename)
          }
        }
      end

      class Tutorial

        attr_reader :name, :current_item

        DELAY = 1 # seconds

        def initialize(console_instance, tutorial_path, name = File.basename(tutorial_path))
          @console_instance = console_instance
          @steps = load_tutorial(tutorial_path)
          @name = name
          @current_step = -1
          @context = nil # SandBox
          @original_wrap_in_undo = nil
          @original_binding = nil
        end

        def start
          # Change execution context to instance of SandBox
          @context = SandBox.new(self)
          @original_binding = @console_instance.instance_variable_get(:@binding) # TODO: This does not update the setting in the dialog
          binding = self.class.object_binding(@context)
          @console_instance.instance_variable_set(:@binding, binding)
          # Enable wrap in undo
          @original_wrap_in_undo = @console_instance.instance_variable_get(:@settings)[:wrap_in_undo]
          @console_instance.instance_variable_get(:@settings)[:wrap_in_undo] = true # TODO: Does this update setting in dialog? No
          # Listen for result
          @console_instance.on(:result_printed, &method(:on_result))
          @console_instance.on(:error_printed, &method(:on_error))
          # Go to first step
          next_step
        end

        def next_step
          # Increase step counter
          @current_step += 1
          if @current_step >= @steps.length
            # TODO: Ask whether to start next tutorial (if there exist) => requires method to list existing tutorials
            quit
          end
          # Print description text
          @current_item = @steps[@current_step]
          eval(@current_item[:preparation_code]) if @current_item[:preparation_code]
          show_message(@current_item[:text]) if @current_item[:text]
          if @current_item[:load_code]
            code = URI.decode(@current_item[:load_code])
            # TODO: support prev
            # item.load_code = prev_code + item.load_code[4..999999] if item.load_code && !item.load_code.empty? && item.load_code[0..3] == 'prev'
            load_code(code)
          end
        end

        def quit
          # Remove listeners for result
          @console_instance.off(:result_printed, &method(:on_result))
          @console_instance.off(:error_printed, &method(:on_error))
          # Change execution context back to original
          @console_instance.instance_variable_set(:@binding, @original_binding)
          # Set wrap in undo back to original
          @console_instance.instance_variable_get(:@settings)[:wrap_in_undo] = @original_wrap_in_undo # TODO: Does this update setting in dialog? No
        end

        def show_message(html_string)
          @console_instance.bridge.call('window.addHtmlToOutput', html_string) unless html_string.empty?
        end

        def load_code(code)
          @console_instance.bridge.call('window.insertInConsoleEditor', code)
        end

        def demonstrate_solution(solution = @current_item[:solution])
          return # Not yet supported
          if solution
            solution.each{ |solution_step|
              show_message(solution_step[:text]) if solution_step[:text]
              # eval(solution_step[:code]) if solution_step[:code]
              load_code(solution_step[:code]) if solution_step[:code]
              # TODO: add JS function to evaluate
              # TODO: This is asynchronous, wait until finished!
              # wait for :timeout before next iteration, if timeout
            }
          end
        end

        private

        def load_tutorial(filepath)
          return File.open(filepath, 'r'){ |f|
            JSON.parse(f.read, :symbolize_names => true)
          }.
          # The tutorial format uses a dictionary with step numbers as key, 
          # we use a list where indices correspond to step numbers.
          # Convert to tuple list and sort by first tuple element (since they are unique), 
          # then select of all tuples the second element.
          sort_by{ |tuple| tuple.first.to_s.to_i }.map{ |tuple|
            item = tuple.last
            [:text, :answer, :ok, :error].each{ |key|
              # TryRuby files have some entries URL-encoded.
              item[key] = URI.decode(item[key]) if item[key]
            }
            item
          }
        end

        def on_result(result, result_string, metadata)
          # Check if output matches the defined answer regexp.
          # and print status message
          valid = nil
          if @current_item[:answer] && !@current_item[:answer].empty?
            # TODO: instead of stringified result, tryruby needs access to all the concatenated stdout since user input.
            valid = !result_string.chomp.match(@current_item[:answer]).nil?
          elsif @current_item[:answer_code] && !@current_item[:answer_code].empty?
            valid = !!eval("proc{ |result| #{@current_item[:answer_code]} }").call(result)
          end
          case valid
          when true
            # Defer action so that result is printed first.
            delay(0) {
              show_message(@current_item[:ok])
              delay(2) {
                next_step
              }
            }
          when false
            delay(0) {
              show_message(@current_item[:error])
            }
          else
            delay(0) {
              next_step
            }
          end
        end

        def on_error(exception, message, metadata)
          # Check if output matches the defined answer regexp.
          # and print status message
          valid = nil
          if @current_item[:answer] && !@current_item[:answer].empty?
            valid = !message.chomp.match(@current_item[:answer]).nil?
          elsif @current_item[:answer_code] && !@current_item[:answer_code].empty?
            valid = !!eval("proc{ |result| #{@current_item[:answer_code]} }").call(exception)
          end
          case valid
          when true
            # Defer action so that result is printed first.
            delay(0) {
              show_message(@current_item[:ok])
              delay(2) {
                next_step
              }
            }
          when false
            delay {
              show_message(@current_item[:error])
            }
          else
            delay(0) {
              next_step
            }
          end
        end

        def delay(duration=DELAY, &block)
          UI.start_timer(duration, false, &block)
        end

        class SandBox

          def initialize(tutorial)
            @tutorial = tutorial
          end

          def inspect
            return @tutorial.name # print something tutorial name, analog like what main prints
          end

          def go!
            delay(0) {
              @tutorial.next_step
            }
            nil # TODO: avoid that nil is printed to the console?
          end
          alias_method :skip, :go!

          def quit
            @tutorial.quit
            nil # TODO: avoid that nil is printed to the console?
          end

          def show
            solution = @tutorial.current_item[:solution]
            if solution
              demonstrate_solution(solution)
            else
              @tutorial.show_message(TRANSLATE['Sorry, I don\'t know the solution either.'])
            end
            nil # TODO: avoid that nil is printed to the console?
          end

        end

      end

    end

  end

end

# Get an object's binding with correct nesting, as if 'binding' was called
# in the original class definition.
# @param object [Object]
# @return [Binding]
def (AE::ConsolePlugin::FeatureRubyTutorials::Tutorial).object_binding(object)
  object.instance_eval('binding')
end
