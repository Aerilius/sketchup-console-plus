require 'json'
require_relative '../bridge'

module AE

  module ConsolePlugin

    class FeatureRubyTutorials

      TRY_RUBY_FILENAME = 'try_ruby.json'

      @@current_running_tutorial ||= nil

      def initialize(app)
        app.plugin.on(:console_added){ |console_instance|

          dialog = console_instance.dialog

          # Callback from webdialog menu
          dialog.on('get_tutorials') { |action_context|
            action_context.resolve(FeatureRubyTutorials.find_tutorials.map{ |filepath|
              {
                :filepath => filepath,
                :display_name => filepath_to_title(filepath)
              }
            })
          }
          dialog.on('get_next_tutorial_and_step') { |action_context|
            tutorial_paths = FeatureRubyTutorials.find_tutorials
            next_tutorial = console_instance.settings[:ruby_tutorials_next_tutorial] || tutorial_paths.find{ |filepath| filepath[TRY_RUBY_FILENAME] }
            next_step = console_instance.settings[:ruby_tutorials_next_step] || 1
            action_context.resolve([next_tutorial, next_step])
          }
          dialog.on('start_tutorial') { |action_context, tutorial_path, next_step|
            FeatureRubyTutorials.start_tutorial(console_instance, tutorial_path, next_step)
          }

        }
        # Start-up notification on first start.
        if app.settings[:first_start, true]
          app.settings[:first_start] = false
          on_first_start
        end
      end

      def get_javascript_path
        return 'feature_ruby_tutorials.js'
      end

      private

      def filepath_to_title(filepath)
        return to_title_case(File.basename(filepath, '.json')).gsub(/_/, ' ')
      end

      def to_title_case(string)
        return string.split(/[\s_-]+/).map(&:capitalize).join(' ')
      end

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
          action_context.resolve(FeatureRubyTutorials.find_tutorials.
          select{ |tutorial_path| !tutorial_path[TRY_RUBY_FILENAME] }.
          map{ |tutorial_path|
            {
              :filepath => tutorial_path,
              :display_name => filepath_to_title(tutorial_path)
            }
          })
        }
        startup_dialog.on('start_try_ruby') { |action_context|
          try_ruby_path = FeatureRubyTutorials.find_tutorials.find{ |path| path[TRY_RUBY_FILENAME] }
          FeatureRubyTutorials.open_console_with_tutorial(try_ruby_path)
          startup_dialog.close
        }
        startup_dialog.on('start_tutorial') { |action_context, tutorial_filepath, next_step|
          FeatureRubyTutorials.open_console_with_tutorial(tutorial_filepath, next_step)
          startup_dialog.close
        }
        startup_dialog.on('close') { |action_context|
          startup_dialog.close()
        }

        startup_dialog.show
      end

      def self.start_tutorial(console_instance, tutorial_path, next_step=1)
        @@current_running_tutorial.quit if @@current_running_tutorial
        tutorial = Tutorial.new(console_instance, tutorial_path)
        tutorial.start(next_step)
        @@current_running_tutorial = tutorial
      end

      def self.open_console_with_tutorial(tutorial_filepath, next_step=1)
        console_instance = ConsolePlugin.open
        console_instance.on(:shown) {
          # Wait until JavaScript is loaded.
          UI.start_timer(1, false) {
            self.start_tutorial(console_instance, tutorial_filepath, next_step)
          }
        }
      end

      def self.find_tutorials
        filepaths = Dir.glob(File.join(PATH, 'Resources', 'en-US', 'tutorials', '*.json')).map{ |filepath|
          locale_filepath = File.join(PATH, 'Resources', Sketchup.get_locale, 'tutorials', File.basename(filepath))
          if File.exist?(locale_filepath)
            locale_filepath
          else
            filepath
          end
        }.sort
        filepaths.unshift(filepaths.delete(filepaths.find{ |filepath| filepath[TRY_RUBY_FILENAME] }))
        return filepaths
      end

      class Tutorial

        attr_reader :title, :current_item, :current_step, :steps

        DELAY = 1 # seconds

        def initialize(console_instance, tutorial_path)
          @tutorial_path = tutorial_path
          @console_instance = console_instance
          @steps = []
          @title = ''
          @current_step = -1
          @tip_counter = 0
          @binding = nil # SandBox binding
          @original_wrap_in_undo = nil
          @original_binding = nil
          @ignore_command_result = false
          load_tutorial(tutorial_path)
        end

        def start(initial_step=nil)
          # Change execution context to instance of SandBox
          @original_binding = @console_instance.instance_variable_get(:@binding) # TODO: This does not update the setting in the dialog
          context = SandBox.new(self)
          @binding = FeatureRubyTutorials.object_binding(context)
          @console_instance.instance_variable_set(:@binding, @binding)
          # Enable wrap in undo
          @original_wrap_in_undo = @console_instance.instance_variable_get(:@settings)[:wrap_in_undo]
          @console_instance.instance_variable_get(:@settings)[:wrap_in_undo] = true # TODO: This does not update the setting in the dialog
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
          @console_instance.bridge.on('next_tip') { show_tip }
          @console_instance.bridge.on('show_solution') { show_solution }
          @console_instance.on(:closed) { quit }
          @console_instance.bridge.call('Console.clear')
          # Go to first step
          next_step(initial_step)
        end

        def next_step(target=nil)
          # Increase step counter
          @current_step = (target.nil?) ? @current_step + 1 : target - 1
          if @current_step >= @steps.length
            # Ask whether to start next tutorial
            next_tutorial, next_step = get_next_tutorial_and_step()
            if !next_tutorial.nil?
              @console_instance.bridge.call('FeatureRubyTutorials.showTutorialSelector')
            end
            return quit
          end
          @current_item = @steps[@current_step]
          # Reset tip counter for tips of the current step
          @tip_counter = 0
          # Prepare the model for this step if something needs to be prepared (entities drawn, model loaded).
          if @current_item[:preparation_code]
            begin
              evaluate(@current_item[:preparation_code], @binding)
            rescue => error
              AE::ConsolePlugin.error(error)
            end
          end
          # Print description text
          show_instruction(@current_item) if @current_item[:text]
          if @current_item[:load_code]
            code = @current_item[:load_code]
            load_code(code)
          end
        end

        def get_next_tutorial_and_step
          # Tutorial finished
          if @current_step >= @steps.length
            tutorial_paths = FeatureRubyTutorials.find_tutorials
            next_tutorial = tutorial_paths[tutorial_paths.index(@tutorial_path) + 1] # or nil
            next_step = 1
          else
            next_tutorial = @tutorial_path
            next_step = @current_step + 1
          end
          return next_tutorial, next_step
        end

        def quit
          # Save status
          @console_instance.settings[:ruby_tutorials_next_tutorial],
          @console_instance.settings[:ruby_tutorials_next_step] = get_next_tutorial_and_step
          # Remove listeners for result
          @console_instance.off(:result, &@on_result)
          @console_instance.off(:error, &@on_error)
          @console_instance.off(:eval, &@on_eval)
          @console_instance.off(:puts, &@on_puts)
          @console_instance.off(:print, &@on_print)
          # Change execution context back to original
          @console_instance.instance_variable_set(:@binding, @original_binding)
          # Set wrap in undo back to original
          @console_instance.instance_variable_get(:@settings)[:wrap_in_undo] = @original_wrap_in_undo
          @@current_running_tutorial = nil
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
          @console_instance.bridge.call('FeatureRubyTutorials.addHtmlToOutput', html_string) unless html_string.empty?
        end

        def load_code(code)
          @console_instance.bridge.call('FeatureRubyTutorials.insertInConsoleEditor', code)
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
            @console_instance.bridge.call('FeatureRubyTutorials.evaluateInConsole', @current_item[:solution_code])
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
          @title = json[:title] if json[:title]
          @steps = json[:steps] if json[:steps]
        end

        def validation_defined?
          return (@current_item[:validate_result_regexp] && !@current_item[:validate_result_regexp].empty?) ||
                 (@current_item[:validate_result_code] && !@current_item[:validate_result_code].empty?) ||
                 (@current_item[:validate_stdout_regexp] && !@current_item[:validate_stdout_regexp].empty?) ||
                 (@current_item[:validate_error_regexp] && !@current_item[:validate_error_regexp].empty?) ||
                 (@current_item[:validate_error_code] && !@current_item[:validate_error_code].empty?)
        end

        def validate_result(result, metadata)
          return @ignore_command_result = false if @ignore_command_result
          return unless @current_item
          if validation_defined?
            valid = nil
            if @current_item[:validate_result_regexp] && !@current_item[:validate_result_regexp].empty?
              if !result.nil?
                result_string = metadata[:result_string]
                valid = !result_string.match(@current_item[:validate_result_regexp]).nil?
              end
            elsif @current_item[:validate_result_code] && !@current_item[:validate_result_code].empty?
              if !result.nil?
                code = "proc{ |result| #{@current_item[:validate_result_code]} }"
                begin
                  proc = evaluate(code, @binding)
                  valid = !!proc.call(result)
                rescue => error
                  AE::ConsolePlugin.error(error)
                end
              end
            elsif @current_item[:validate_stdout_regexp] && !@current_item[:validate_stdout_regexp].empty?
              message = @combined_stdout
              valid = !message.match(@current_item[:validate_stdout_regexp]).nil?
            end
            when_console_message_printed(metadata[:id]).then{
              case valid
              when true
                show_message(@current_item[:ok]) if @current_item[:ok]
                delay(1.5) {
                  next_step
                }
              when false
                show_message(@current_item[:error]) if @current_item[:error]
              end
            }
          else
            delay(0) {
              next_step
            }
          end
        end

        def validate_error(exception, metadata)
          return @ignore_command_result = false if @ignore_command_result
          return unless @current_item
          if validation_defined?
            valid = nil
            if @current_item[:validate_error_regexp] && !@current_item[:validate_error_regexp].empty?
              message = metadata[:message]
              valid = !message.chomp.match(@current_item[:validate_error_regexp]).nil?
            elsif @current_item[:validate_error_code] && !@current_item[:validate_error_code].empty?
              code = "proc{ |exception| #{@current_item[:validate_error_code]} }"
              begin
                proc = evaluate(code, @binding)
                valid = !!proc.call(exception)
              rescue => error
                AE::ConsolePlugin.error(error)
              end
            end
            when_console_message_printed(metadata[:id]).then{
              case valid
              when true
                # Defer action so that result is printed first.
                show_message(@current_item[:ok]) if @current_item[:ok]
                delay(1) {
                  next_step
                }
              when false
                show_message(@current_item[:error]) if @current_item[:error]
              end
            }
          else
            delay(0) {
              next_step
            }
          end
        end

        def when_console_message_printed(id)
          return @console_instance.bridge.get('FeatureRubyTutorials.waitForMessage', id)
        end

        def evaluate(code, binding=FeatureTutorials.object_binding(Object.new))
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
            @tutorial.instance_variable_set(:@ignore_command_result, true)
            @tutorial.delay(0) {
              @tutorial.next_step(target)
            }
            ''
          end
          alias_method :skip, :go!

          def quit
            @tutorial.instance_variable_set(:@ignore_command_result, true)
            if @tutorial.current_step < @tutorial.steps.length - 1
              @tutorial.show_message(TRANSLATE['You proceded up to step %0 of %1!', @tutorial.current_step + 1, @tutorial.steps.length])
            end
            @tutorial.show_message(TRANSLATE['See you next time!'])
            @tutorial.quit
            ''
          end

          def tip
            @tutorial.instance_variable_set(:@ignore_command_result, true)
            @tutorial.delay(0) {
              @tutorial.show_tip
            }
            ''
          end

          def show
            @tutorial.instance_variable_set(:@ignore_command_result, true)
            @tutorial.delay(0) {
              @tutorial.show_solution
            }
            ''
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
def (AE::ConsolePlugin::FeatureRubyTutorials).object_binding(object)
  object.instance_eval('binding')
end
