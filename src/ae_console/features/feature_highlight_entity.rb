module AE

  module ConsolePlugin

    class FeatureHighlightEntity

      require(File.join(PATH, 'features', 'entity_highlight_tool.rb'))

      def initialize(app)
        app.plugin.on(:console_added, &method(:initialize_console))
        @is_active = false
        @instance = nil
        @model = nil # Reference used while highlighting is active
      end

      def initialize_console(console)
        dialog = console.dialog

        dialog.on('highlight_entity') { |action_context, id_string|
          begin
            object = ObjectSpace._id2ref(id_string.to_i(16) >> 1)
            select_highlighter_tool{ |tool|
              tool.highlight(entity)
            }
            # RangeError if no entity found for given id,
            # TypeError "Reference to deleted entity" if entity has been deleted.
          rescue RangeError, TypeError => e
            action_context.reject
          end
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
          select_highlighter_tool{ |tool|
            tool.highlight(point)
          }
        }

        dialog.on('highlight_vector') { |action_context, array_xyz|
          vector = Geom::Vector3d.new(array_xyz)
          select_highlighter_tool{ |tool|
            tool.highlight(vector)
          }
        }

        dialog.on('highlight_stop') {
          deselect_highlighter_tool()
        }
      end

      def select_highlighter_tool(&action)
        unless @is_active
          @model ||= Sketchup.active_model
          @instance ||= EntityHighlightTool.new
          @model.tools.push_tool(@instance)
        end
        action.call(@instance) if block_given?
        @is_active = true
      end

      def deselect_highlighter_tool
        if @is_active && @model
          @model.tools.pop_tool
          @model = nil
          @is_active = false
        end
      end

      def get_javascript_path
        return 'feature_highlight_entity.js'
      end

    end # class FeatureHighlightEntity

  end # module ConsolePlugin

end # module AE
