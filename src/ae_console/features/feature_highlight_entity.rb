module AE

  module ConsolePlugin

    class FeatureHighlightEntity

      require(File.join(PATH, 'features', 'entity_highlight_tool.rb'))

      def initialize(app)
        app.plugin.on(:console_added, &method(:initialize_console))
      end

      def initialize_console(console)
        dialog = console.dialog
        is_active = false
        instance = nil
        model = nil # Reference used while highlighting is active

        dialog.on('highlight_entity') { |action_context, id|
          object = ObjectSpace._id2ref(id.to_i)
          model = (object.respond_to?(:model)) ? object.model || Sketchup.active_model : Sketchup.active_model
          unless is_active
            instance ||= EntityHighlightTool.new
            model.tools.push_tool(instance)
          end
          instance.highlight(object)
          is_active = true
          # Exceptions (invalid/deleted entity) will reject the webdialog's promise.
        }

        dialog.on('highlight_point') { |action_context, array_xyz, unit|
          case unit
          when 'm' then
            array_xyz.map! { |c| c.m }
          when 'feet' then
            array_xyz.map! { |c| c.feet }
          when 'inch' then
            array_xyz.map! { |c| c.inch }
          when 'cm' then
            array_xyz.map! { |c| c.cm }
          when 'mm' then
            array_xyz.map! { |c| c.mm }
          end
          point = Geom::Point3d.new(array_xyz)
          model = Sketchup.active_model
          unless is_active
            instance ||= EntityHighlightTool.new
            model.tools.push_tool(instance)
          end
          instance.highlight(point)
          is_active = true
        }

        dialog.on('highlight_vector') { |action_context, array_xyz|
          vector = Geom::Vector3d.new(array_xyz)
          model = Sketchup.active_model
          unless is_active
            instance ||= EntityHighlightTool.new
            model.tools.push_tool(instance)
          end
          instance.highlight(vector)
          is_active = true
        }

        dialog.on('highlight_stop') {
          if is_active && model
            model.tools.pop_tool
            model = nil
            is_active = false
          end
        }
      end

      def get_javascript_path
        return 'feature_highlight_entity.js'
      end

    end # class FeatureHighlightEntity

  end # module ConsolePlugin

end # module AE
