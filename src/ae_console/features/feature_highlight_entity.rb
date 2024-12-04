module AE

  module ConsolePlugin

    class FeatureHighlightEntity

      require(File.join(PATH, 'features', 'entity_highlight_tool.rb'))

      def initialize(app)
        app.plugin.on(:console_added, &method(:initialize_console))
        @is_active = false
        @instance = nil
        @model = nil # Reference used while highlighting is active
        @id_map = {}
      end

      def initialize_console(console)
        # In SketchUp 2024, the "inspect" string does not seem to encode the 
        # object_id anymore. There is no direct way to map logged string
        # representations of entities to actual entities.
        # As a work-around, we intercept the "eval" return values and store the
        # mapping in a hash.
        console.on(:result) { |result, metadata|
          result_string = metadata[:result_string]
          if result.is_a?(Sketchup::Drawingelement) ||
              result.is_a?(Sketchup::Curve) ||
              result.is_a?(Sketchup::Vertex) ||
              result.is_a?(Geom::Point3d) ||
              result.is_a?(Geom::Vector3d) ||
              result.is_a?(Geom::BoundingBox)
            memorize_entity_object_id(result, result_string)
          elsif result.is_a?(Enumerable)
            obj_strings = result_string.sub(/^\[\s*/, '').sub(/\s*\]$/, '').split(/,\s*/)
            if result.length == obj_strings.length
              result.zip(obj_strings).each{ |obj, obj_string|
                memorize_entity_object_id(obj, obj_string)
              }
            end
          end
        }

        dialog = console.dialog

        dialog.on('highlight_entity') { |action_context, id_string|
          begin
            entity = id_string_to_object_id(id_string)
          rescue RangeError => e
            # RangeError if no entity found for given id.
            action_context.reject
          end
          select_highlighter_tool{ |tool|
            begin
              tool.highlight(entity)
            rescue TypeError => e
              # TypeError "Reference to deleted entity" if entity has been deleted.
              action_context.reject(entity.inspect)
            end
          }
        }

        dialog.on('highlight_point') { |action_context, array_xyz, unit|
          point = coordinates_array_to_point(array_xyz, unit)
          select_highlighter_tool{ |tool|
            tool.highlight(point)
          }
        }

        dialog.on('highlight_vector') { |action_context, array_xyz|
          vector = coordinates_array_to_vector(array_xyz)
          select_highlighter_tool{ |tool|
            tool.highlight(vector)
          }
        }

        dialog.on('highlight_multiple') { |action_context, elements_map|
          entities = []
          elements_map['entity'].each{ |id_string|
            begin
              entity = id_string_to_object_id(id_string)
              next if entity.respond_to?(:valid?) && !entity.valid?
              entities << entity
            rescue RangeError
              next
            end
          }
          elements_map['point'].each{ |array_xyz, unit|
            entities << coordinates_array_to_point(array_xyz, unit)
          }
          elements_map['vector'].each{ |array_xyz|
            entities << coordinates_array_to_vector(array_xyz)
          }
          select_highlighter_tool{ |tool|
            tool.highlight(*entities)
          }
        }

        dialog.on('highlight_stop') {
          deselect_highlighter_tool()
        }

        dialog.on('get_color') { |action_context, id_string|
          begin
            entity = id_string_to_object_id(id_string)
            action_context.resolve entity.to_a
            # RangeError if no entity found for given id,
            # TypeError "Reference to deleted entity" if entity has been deleted.
          rescue RangeError, TypeError => e
            action_context.reject
          end
        }
      end

      def memorize_entity_object_id(obj, obj_string)
        if obj.is_a?(Sketchup::Drawingelement) ||
            obj.is_a?(Sketchup::Curve) ||
            obj.is_a?(Sketchup::Vertex) ||
            obj.is_a?(Geom::Point3d) ||
            obj.is_a?(Geom::Vector3d) ||
            obj.is_a?(Geom::BoundingBox)
          match = obj_string.match(/#<#{obj.class}\:([0-9abcdefx]+)>/)
          if match
            id_string = match[1]
            object_id = obj.object_id
            # Save the object_id for the inspect ID string.
            @id_map[id_string] = object_id
          end
        end
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

      def id_string_to_object_id(id_string)
        # Decode the "inspect" string of Ruby objects and extract the object_id.
        #
        # The following does not work anymore for SketchUp entities in 2024.
        # object_id = id_string.to_i(16) >> 1
        # obj = ObjectSpace._id2ref(object_id)
        # return obj
        #
        # As a work-around, we capture the IDs on evaluation and memorize them.
        object_id = @id_map[id_string]
        return if object_id.nil?
        obj = ObjectSpace._id2ref(object_id)
        return obj
      end

      def coordinates_array_to_point(array_xyz, unit)
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
        return Geom::Point3d.new(array_xyz)
      end

      def coordinates_array_to_vector(array_xyz)
        return Geom::Vector3d.new(array_xyz)
      end

      def get_javascript_path
        return 'feature_highlight_entity.js'
      end

    end # class FeatureHighlightEntity

  end # module ConsolePlugin

end # module AE
