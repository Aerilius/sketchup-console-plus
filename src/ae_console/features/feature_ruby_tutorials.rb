require 'json'
require_relative '../bridge'

module AE

  module ConsolePlugin

    class FeatureRubyTutorials

      TRY_RUBY_FILENAME = 'try_ruby.json'

      @@current_running_tutorial = nil

      def initialize(app)
        app.plugin.on(:console_added){ |console_instance|

          dialog = console_instance.dialog

          # Callback from webdialog menu
          dialog.on('get_tutorials') { |action_context|
            action_context.resolve(find_tutorials.map{ |tutorial_filename|
              {
                :filename => tutorial_filename,
                :display_name => to_title_case(File.basename(tutorial_filename, '.json'))
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
        tutorial_path = File.join(PATH, 'Resources', 'en-US', 'tutorials', tutorial_filename) unless File.exist?(tutorial_path)
        @@current_running_tutorial.quit if @@current_running_tutorial
        tutorial = Tutorial.new(console_instance, tutorial_path)
        tutorial.start
        @@current_running_tutorial = tutorial
      end

      def find_tutorials
        return Dir.glob(File.join(PATH, 'Resources', 'en-US', 'tutorials', '*.json')).map{ |tutorial_path|
          File.basename(tutorial_path)
        }
      end

      def to_title_case(string)
        string.split(/[\s_-]+/).map(&:capitalize).join(' ')
      end
      private :to_title_case

      def on_first_start
        properties = {
            :dialog_title    => TRANSLATE['Welcome to Ruby Console+'],
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
              :display_name => to_title_case(File.basename(tutorial_filename, '.json'))
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

        attr_reader :title, :current_item, :current_step, :steps

        DELAY = 1 # seconds

        def initialize(console_instance, tutorial_path)
          @console_instance = console_instance
          @steps = []
          @title = ''
          @current_step = -1
          @tip_counter = 0
          @context = nil # SandBox
          @original_wrap_in_undo = nil
          @original_binding = nil
          load_tutorial(tutorial_path)
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
          @combined_stdout = ''
          @on_eval = proc{ |command, metadata|
            @combined_stdout.clear
          }
          @on_puts = proc{ |message, metadata|
            @combined_stdout << message << $/
          }
          @on_print = proc{ |message, metadata|
            @combined_stdout << message
          }
          @on_result = proc{ |result, metadata|
            validate_result(result, metadata)
            @combined_stdout.clear
          }
          @on_error = proc{ |exception, metadata|
            validate_error(exception, metadata)
            @combined_stdout.clear
          }
          @console_instance.on(:result, &@on_result)
          @console_instance.on(:error, &@on_error)
          @console_instance.on(:puts, &@on_puts)
          @console_instance.on(:print, &@on_print)
          @console_instance.bridge.on(:next_tip) { show_tip }
          @console_instance.bridge.on(:show_solution) { show_solution }
          @console_instance.on(:closed) { quit }
          # Go to first step
          next_step
        end

        def next_step(target=nil)
          # Increase step counter
          @current_step = (target.nil?) ? @current_step + 1 : target - 1
          if @current_step >= @steps.length
            # TODO: Ask whether to start next tutorial (if there exist) => requires method to list existing tutorials
            quit
          end
          @current_item = @steps[@current_step]
          # Reset tip counter for tips of the current step
          @tip_counter = 0
          # Prepare the model for this step if something needs to be prepared (entities drawn, model loaded).
          if @current_item[:preparation_code]
            evaluate(@current_item[:preparation_code])
          end
          # Print description text
          show_instruction(@current_item) if @current_item[:text]
          if @current_item[:load_code]
            code = @current_item[:load_code]
            # TODO: json: support prev or remove prev
            # item.load_code = prev_code + item.load_code[4..999999] if item.load_code && !item.load_code.empty? && item.load_code[0..3] == 'prev'
            load_code(code)
          end
        end

        def quit
          # Remove listeners for result
          @console_instance.off(:result, &@on_result)
          @console_instance.off(:error, &@on_error)
          @console_instance.off(:eval, &@on_eval)
          @console_instance.off(:puts, &@on_puts)
          @console_instance.off(:print, &@on_print)
          # Change execution context back to original
          @console_instance.instance_variable_set(:@binding, @original_binding)
          # Set wrap in undo back to original
          @console_instance.instance_variable_get(:@settings)[:wrap_in_undo] = @original_wrap_in_undo # TODO: Does this update setting in dialog? No
        end

        def show_instruction(step)
          html_string = step[:text]
          if step[:tip] || step[:solution_code]
            buttons_div = '<div class="ruby_tutorials_toolbar">'
            tip = step[:tip]
            if tip
              number_of_tips = (tip.is_a?(Array)) ? tip.length : 1
              buttons_div += (<<-EOT)
              <button class="tip" title="#{TRANSLATE['Tip']}" onclick="this.count = this.count || #{number_of_tips}; this.disabled = (--this.count <= 0); Bridge.call('next_tip')">
                  <img src="../images/tip.svg" alt="tip">
              </button>
              EOT
            end
            if step[:solution_code]
              buttons_div += (<<-EOT)
              <button class="solution" title="#{TRANSLATE['Solution']}" onclick="Bridge.call('show_solution'); this.disabled = true">
                  <img src="../images/solution.svg" alt="solution">
              </button>
              EOT
            end
            buttons_div += "</div>"
            html_string += buttons_div
          end
          show_message(html_string)
        end

        def show_message(html_string)
          @console_instance.bridge.call('window.addHtmlToOutput', html_string) unless html_string.empty?
        end

        def load_code(code)
          @console_instance.bridge.call('window.insertInConsoleEditor', code)
        end

        def show_tip
          return unless @current_item
          tip = @current_item[:tip]
          if tip.is_a?(Array) && @tip_counter < tip.length
            show_message(tip[@tip_counter])
            @tip_counter += 1
          elsif tip.is_a?(String) && !tip.empty? && @tip_counter == 0
            show_message(tip)
            @tip_counter += 1
          else
            show_message(TRANSLATE['Sorry, I don\'t have any tips.'])
          end
        end

        def show_solution
          return unless @current_item
          if @current_item[:solution_code]
            @console_instance.bridge.call('evaluateInConsole', @current_item[:solution_code])
          else
            show_message(TRANSLATE['Sorry, I don\'t know the solution either.'])
          end
        end

        def delay(duration=DELAY, &block)
          UI.start_timer(duration, false, &block)
        end

        private

        def load_tutorial(filepath)
          json = File.open(filepath, 'r'){ |f|
            JSON.parse(f.read, :symbolize_names => true)
          }
          @title = json[:title]
          @steps = json[:steps]
        end

        def validation_defined?
          return (@current_item[:validate_result_regexp] && !@current_item[:validate_result_regexp].empty?) ||
                 (@current_item[:validate_result_code] && !@current_item[:validate_result_code].empty?) ||
                 (@current_item[:validate_stdout_regexp] && !@current_item[:validate_stdout_regexp].empty?) ||
                 (@current_item[:validate_error_regexp] && !@current_item[:validate_error_regexp].empty?) ||
                 (@current_item[:validate_error_code] && !@current_item[:validate_error_code].empty?)
        end

        def validate_result(result, metadata)
          return unless @current_item
          if validation_defined?
            valid = nil
            # TODO: json: rename in :validate_result_regexp, :validate_stdout_regexp
            # TODO: instead of stringified result, tryruby needs access to all the concatenated stdout since user input.
            if @current_item[:validate_result_regexp] && !@current_item[:validate_result_regexp].empty?
              if !result.nil?
                result_string = metadata[:result_string]
                valid = !result_string.match(@current_item[:validate_result_regexp]).nil?
              end
            elsif @current_item[:validate_result_code] && !@current_item[:validate_result_code].empty?
              if !result.nil?
                code = "proc{ |result| #{@current_item[:validate_result_code]} }"
                proc = evaluate(code, @context)
                valid = !!proc.call(result)
              end
            elsif @current_item[:validate_stdout_regexp] && !@current_item[:validate_stdout_regexp].empty?
              message = @combined_stdout
              valid = !message.match(@current_item[:validate_stdout_regexp]).nil?
            end
            when_console_message_printed(metadata[:id]).then{
              case valid
              when true
                show_message(@current_item[:ok])
                delay(1) {
                  next_step
                }
              when false
                show_message(@current_item[:error])
              end
            }
          else
            next_step
          end
        end

        def validate_error(exception, metadata)
          return unless @current_item
          if validation_defined?
            valid = nil
            # TODO: json: rename in :validate_error_regexp
            if @current_item[:validate_error_regexp] && !@current_item[:validate_error_regexp].empty?
              message = metadata[:message]
              valid = !message.chomp.match(@current_item[:validate_error_regexp]).nil?
            elsif @current_item[:validate_error_code] && !@current_item[:validate_error_code].empty?
              code = "proc{ |exception| #{@current_item[:validate_error_code]} }"
              proc = evaluate(code, @context)
              valid = !!proc.call(exception)
            end
            when_console_message_printed(metadata[:id]).then{
              case valid
              when true
                # Defer action so that result is printed first.
                show_message(@current_item[:ok])
                delay(1) {
                  next_step
                }
              when false
                show_message(@current_item[:error])
              end
            }
          else
            next_step
          end
        end

        def when_console_message_printed(id)
          return @console_instance.bridge.get('waitForMessage', id)
        end

        def evaluate(code, context=Object.new)
          binding = (AE::ConsolePlugin::FeatureRubyTutorials::Tutorial).object_binding(context)
          return eval(code, binding)
        end

        # Not a true sandbox, but a context to run code outside the tutorial 
        # implementation without polluting each other's scope with variables.
        # Only methods that should be available as commands during the tutorial.
        class SandBox

          def initialize(tutorial)
            @tutorial = tutorial
          end

          def inspect
            return @tutorial.title
          end

          def go!(target=nil)
            @tutorial.delay(0) {
              @tutorial.next_step(target)
            }
            nil # TODO: avoid that nil is printed to the console?
          end
          alias_method :skip, :go!

          def quit
            if @tutorial.current_step < @tutorial.steps.length - 1
              @tutorial.show_message(TRANSLATE['You proceded up to step %0 of %1!', @tutorial.current_step + 1, @tutorial.steps.length])
            end
            @tutorial.show_message(TRANSLATE['See you next time!'])
            @tutorial.quit
            nil # TODO: avoid that nil is printed to the console?
          end

          def tip
            @tutorial.delay(0) {
              @tutorial.show_tip
            }
            nil # TODO: avoid that nil is printed to the console?
          end

          def show
            @tutorial.delay(0) {
              @tutorial.show_solution
            }
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
