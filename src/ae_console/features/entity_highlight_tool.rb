module AE

  module ConsolePlugin

    require(File.join(PATH, 'promise.rb'))

    module EntityDrawingInstructions

      def draw_edges(view, entity, line_color=nil, t=IDENTITY)
        points = entity.vertices.map { |v| view.screen_coords(v.position.transform(t)) }
        view.drawing_color = line_color unless line_color.nil?
        view.draw2d(GL_LINE_STRIP, points)
        # Draw an arrow at the end of the edge/curve/arc to indicate its orientation.
        p1 = points.last
        vec = p1.vector_to(points[-2])
        return unless vec.valid?
        vec.length = 5
        side = vec * Z_AXIS
        arrow = [p1, p1+vec+vec+side, p1+vec+vec-side]
        view.draw2d(GL_POLYGON, arrow)
      end

      def draw_face(view, face, line_color, face_color, t=IDENTITY)
        view.drawing_color = line_color
        face.loops.each { |loop|
          ps = loop.vertices.map { |v| view.screen_coords(v.position.transform(t)) }
          view.draw2d(GL_LINE_LOOP, ps)
        }
        view.drawing_color = face_color
        # Draw the face, this is compatible with concave faces and with holes.
        mesh = face.mesh(0)
        ps   = (1..mesh.count_polygons).map { |i|
          mesh.polygon_points_at(i).map{ |p|
            view.screen_coords(p.transform(t))
          }
        }.flatten
        view.draw2d(GL_TRIANGLES, ps) if Sketchup.version.to_i >= 8 # support of transparent color
      end

      def draw_vertex(view, vertex, color=nil, t=IDENTITY)
        draw_point3d(view, vertex.position, color, t)
      end

      def draw_point3d(view, point, color=nil, t=IDENTITY)
        view.drawing_color = color unless color.nil?
        point   = view.screen_coords(point.transform(t))
        # Round it to pixels.
        point.x = point.x.to_i; point.y = point.y.to_i; point.z = point.z.to_i
        # Draw a cross with radius r.
        r = 3
        view.draw2d(GL_LINES, point + [r, r, 0], point + [-r, -r, 0], point + [r, -r, 0], point + [-r, r, 0])
      end

      # Draw a vector as arrow from point p1 to p2.
      # Since a vector has no fixed position, we place it arbitrarily at the last viewed point or in the center of the
      # screen.
      # @param view [Sketchup::View]
      def draw_vector3d(view, p, vector, color=nil, t=IDENTITY)
        return unless vector.valid? # Invalid vectors cannot be shown.
        # Project to the screen plane.
        p1   = view.screen_coords(p.transform(t))
        p2   = view.screen_coords(p.transform(t) + vector)
        p1.z = p2.z = 0
        vec  = p1.vector_to(p2)
        # If the last viewed point is out of the viewport, take the viewport center.
        w    = view.vpwidth
        h    = view.vpheight
        if p1.x < 0 || p1.x > w || p1.y < 0 || p1.y > h
          p1 = Geom::Point3d.new(w/2, h/2, 0)
          p2 = p1 + vec
        end
        # Clip the second point if it lays outside the viewport.
        p2 = Geom.intersect_line_line([p1, vec], [[0, 0, 0], Y_AXIS]) || p2 if p2.x < 0
        p2 = Geom.intersect_line_line([p1, vec], [[w, 0, 0], Y_AXIS]) || p2 if p2.x > w
        p2 = Geom.intersect_line_line([p1, vec], [[0, 0, 0], X_AXIS]) || p2 if p2.y < 0
        p2 = Geom.intersect_line_line([p1, vec], [[0, h, 0], X_AXIS]) || p2 if p2.y > h
        # Draw the vector direction.
        view.drawing_color = color unless color.nil?
        view.draw2d(GL_LINE_STRIP, p1, p2)
        # Draw an arrow at the end of the vector.
        vec.length = 9 # pixels
        side       = vec * Z_AXIS
        arrow      = [p2, p2-vec-vec+side, p2-vec-vec-side]
        view.draw2d(GL_POLYGON, arrow)
      end

      def draw_unitvector3d(view, p, vector, color=nil, t=IDENTITY)
        return unless vector.valid? # Invalid vectors cannot be shown.
        # Project to the screen plane.
        p1   = view.screen_coords(p.transform(t))
        p2   = view.screen_coords(p.transform(t) + vector)
        p1.z = p2.z = 0
        vec  = p1.vector_to(p2)
        # Scale to a fixed screen space length.
        vec.length = 100
        p2 = p1 + vec
        # Alternatively, set a minimum length limit.
        # if vec.length < 20
        #   vec.length = 20
        #   p2 = p1 + vec
        # end
        # If the last viewed point is out of the viewport, take the viewport center.
        w    = view.vpwidth
        h    = view.vpheight
        if p1.x < 0 || p1.x > w || p1.y < 0 || p1.y > h
          p1 = Geom::Point3d.new(w/2, h/2, 0)
          p2 = p1 + vec
        end
        # Clip the second point if it lays outside the viewport.
        p2 = Geom.intersect_line_line([p1, vec], [[0, 0, 0], Y_AXIS]) || p2 if p2.x < 0
        p2 = Geom.intersect_line_line([p1, vec], [[w, 0, 0], Y_AXIS]) || p2 if p2.x > w
        p2 = Geom.intersect_line_line([p1, vec], [[0, 0, 0], X_AXIS]) || p2 if p2.y < 0
        p2 = Geom.intersect_line_line([p1, vec], [[0, h, 0], X_AXIS]) || p2 if p2.y > h
        # Draw the vector direction.
        view.drawing_color = color unless color.nil?
        view.draw2d(GL_LINE_STRIP, p1, p2)
        # Draw an arrow at the end of the vector.
        vec.length = 9 # pixels
        side       = vec * Z_AXIS
        arrow      = [p2, p2-vec-vec+side, p2-vec-vec-side]
        view.draw2d(GL_POLYGON, arrow)
      end

      def draw_component_group(view, group, line_color, face_color, t=IDENTITY)
        draw_boundingbox(view, group.entities.parent.bounds, line_color, face_color, t)
      end

      def draw_component_instance(view, component_instance, line_color, face_color, t=IDENTITY)
        draw_boundingbox(view, component_instance.definition.bounds, line_color, face_color, t)
      end

      def draw_component_definition(view, component_definition, line_color, face_color, t=IDENTITY)
        draw_boundingbox(view, component_definition.bounds, line_color, face_color, t)
      end

      def draw_boundingbox(view, bounds, line_color, face_color, t=IDENTITY)
        view.drawing_color = line_color
        # Detect 2d bounding box, it needs only one face instead of 6 overlapping faces.
        if bounds.width == 0 || bounds.height == 0 || bounds.depth == 0
          if bounds.width == 0
            ps  = [0, 1, 5, 4].map { |i| bounds.corner(i).transform!(t) }
          elsif bounds.height == 0
            ps  = [0, 1, 3, 2].map { |i| bounds.corner(i).transform!(t) }
          elsif bounds.depth == 0
            ps  = [0, 2, 6, 4].map { |i| bounds.corner(i).transform!(t) }
          end
          # Draw lines
          view.draw2d(GL_LINES, ps.map { |p| view.screen_coords(p) })
          # Draw polygons
          if Sketchup.version.to_i >= 8 # support of transparent color
            view.drawing_color = face_color
            view.draw(GL_QUADS, ps)
          end
        else
          ps  = (0..7).map { |i| bounds.corner(i).transform!(t) }
          # A quad strip around the bounding box
          ps1 = [ps[0], ps[1], ps[2], ps[3], ps[6], ps[7], ps[4], ps[5], ps[0], ps[1]]
          # Two quads not covered by the quad strip
          ps2 = [ps[0], ps[2], ps[6], ps[4], ps[1], ps[3], ps[7], ps[5]]
          # Quad strips ps1, ps2 can be interpreted as lines, but these are missing:
          ps3 = [ps[0], ps[4], ps[1], ps[5], ps[2], ps[6], ps[3], ps[7]]
          # Draw lines
          view.draw2d(GL_LINES, [ps1, ps2, ps3].flatten.map { |p| view.screen_coords(p) })
          # Draw polygons
          if Sketchup.version.to_i >= 8 # support of transparent color
            view.drawing_color = face_color
            view.draw(GL_QUAD_STRIP, ps1)
            view.draw(GL_QUADS, ps2)
          end
        end
      end

      def draw_circle(center, diameter, line_color, t=IDENTITY)
        e = view.camera.eye.vector_to(view.camera.target)
        vec = view.camera.up
        vec.length = diameter
        t_circle = Geom::Transformation.new(center, e, 10.degrees)
        circle = [cp + vec]
        (1..36).each { |i| circle << circle.last.transform(t_circle).transform(t) }
        # Convert to screen space (so that it won't be covered by other geometry).
        circle.map! { |p| view.screen_coords(p) }
        view.drawing_color = line_color
        view.draw2d(GL_LINE_STRIP, circle)
      end
    
    end # module EntityDrawingInstructions

    class EntityHighlightTool

      include EntityDrawingInstructions

# Note: Sketchup entity vertices expose an unexpected behavior depending on the
# active context. When the active context is equal or deeper than the entity's
# context, `position` gives the global coordinates instead of the local coordinates.
# This tool however recursively adds up group/component transformations to convert
# local coordinates into global coordinates. The issue has no impact because in 
# the above described situation Sketchup also returns identity transformations.

      # Used to locate a vector (that has no intrinsic location, only direction).
      @@last_point = ORIGIN # TODO: avoid having a global state through this class variable

      def initialize()
        @entity = nil
        # Global transformations of entities in or below the active path.
        @transformations_active   = []
        # Global transformations for entities in sibling paths, like entities in other instances of a component.
        # In SketchUp, the so-called "components in the rest of the model"
        @transformations_inactive = []
        # Color for the active path.
        @color_active = Sketchup.active_model.rendering_options["HighlightColor"]
        @color_active_transparent = Sketchup::Color.new(@color_active)
        @color_active_transparent.alpha = 0.5
        # Color for sibling path.
        @color_inactive = Sketchup::Color.new(@color_active)
        @color_inactive.alpha = 0.25
        @color_inactive_transparent = Sketchup::Color.new(@color_inactive)
        @color_inactive_transparent.alpha = 0.05
      end

      # Set the entity to highlight.
      # @param entity [Sketchup::Drawingelement, Sketchup::Curve, Sketchup::Vertex, Geom::Point3d, Geom::Vector3d, Geom::BoundingBox]
      def highlight(entity)
        if entity.is_a?(Sketchup::Drawingelement) ||
            entity.is_a?(Sketchup::Curve)  ||
            entity.is_a?(Sketchup::Vertex)
          @entity = entity
          # Find all occurences of the entity (in instances) and collect their transformations.
          @transformations_active = collect_all_active_occurences(entity)
          @transformations_inactive = collect_all_inactive_occurences(entity)
          model = entity.model
        elsif entity.is_a?(Geom::Point3d) ||
            entity.is_a?(Geom::Vector3d) ||
            entity.is_a?(Geom::BoundingBox)
          @entity = entity
          # Point3d, Vector3d, Geom::BoundingBox have no instance path (no position in
          # model nesting hierarchy). So we draw them always relative to the active context.
          model = Sketchup.active_model
          @transformations_active << model.edit_transform
          @transformations_inactive.clear
        else
          @entity = nil
          @transformations_active.clear
          @transformations_inactive.clear
          model = Sketchup.active_model
        end
        model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      # TODO: refactor using strategy pattern? This would require methods (strategies) with same interface but here we have special cases where we set colors etc.
      def draw(view)
        # Drawing settings
        view.drawing_color = @color_active
        view.line_width    = 5

        case @entity
        when nil
          return

        when Geom::Point3d, Sketchup::Vertex
          # Point3d / Vertex
          p1 = (@entity.is_a?(Sketchup::Vertex)) ? @entity.position : @entity
          view.line_width = 3
          view.drawing_color = @color_active
          @transformations_active.each { |t| draw_point3d(view, p1, nil, t) }
          view.drawing_color = @color_inactive
          @transformations_inactive.each { |t| draw_point3d(view, p1, nil, t) } # We only have transformations here for vertices.
          @@last_point = p1

        when Geom::Vector3d
          # Vector3d
          return unless @entity.valid?
          draw_vector3d(view, @@last_point, @entity, @color_active, @transformations_active.first)

        when Sketchup::Edge, Sketchup::Curve, Sketchup::ArcCurve
          # Edge
          @transformations_active.each{ |t| draw_edges(view, @entity, @color_active, t) }
          @transformations_inactive.each{ |t| draw_edges(view, @entity, @color_inactive, t) }

        when Sketchup::Face
          # Face
          @transformations_active.each{ |t| draw_face(view, @entity, @color_active, @color_active_transparent, t) }
          @transformations_inactive.each{ |t| draw_face(view, @entity, @color_inactive, @color_inactive_transparent, t) }

        when Sketchup::Group, Sketchup::ComponentInstance, Sketchup::Image, Sketchup::ComponentDefinition, Geom::BoundingBox
          # Group / Component / Image / Definition / BoundingBox
          bounds = case @entity
          when Sketchup::Group then
            @entity.entities.parent.bounds
          when Sketchup::ComponentDefinition then
            @entity.bounds
          when Geom::BoundingBox then
            @entity
          else
            @entity.definition.bounds
          end
          @transformations_active.each { |t| draw_boundingbox(view, bounds, @color_active, @color_active_transparent, t) }
          @transformations_inactive.each { |t| draw_boundingbox(view, bounds, @color_inactive, @color_inactive_transparent, t) }

        else
          if @entity.is_a?(Sketchup::Drawingelement) && !(@entity.is_a?(Sketchup::Text) && !@entity.has_leader?)
            # Anything else that is not a 2d screen space text (text without leader)
            # For entities with undefined shape, draw a circle around them.
            center = @entity.bounds.center
            # Diameter; consider a minimum for Drawingelements that have no diameter
            diameter = [@entity.bounds.diagonal/2.0, view.pixels_to_model(5, cp)].max
            @transformations_active.each { |t| draw_circle(center, diameter, @color_active, t) }
            @transformations_inactive.each { |t| draw_circle(center, diameter, @color_inactive, t) }
          end
        end
      end

      private

      # Bottom-up breadth search of all transformations of all occurences of the given entity (within nested component instances).
      # It starts from the leaves (!) and multiplies the local transformations up to the root.
      # The initial leaf is the given entity. For all containers encountered on the way to the root (containing entity),
      # their instances are added as further leaves/branches.
      # @param entity [Sketchup::Drawingelement, Sketchup::Curve]
      # @return [Geom::Transformation]
      def collect_all_active_occurences(entity)
        results = []
        queue = []
        entity_transformation = (entity.respond_to?(:transformation)) ? # Sketchup::ComponentInstance, Sketchup::Group, Sketchup::Image
                                entity.transformation :
                                IDENTITY
        queue.push([[entity], entity_transformation])
        until queue.empty?
          path, transformation = *queue.shift
          outer = path.first
          # If the outermost container is already the model, end the search.
          if outer.parent.is_a?(Sketchup::Model) || outer.parent.nil?
            # Check if this occurence of entity is below the active path,
            # that means whether the entity's path contains the active path.
            # Note: Sketchup::Model#active_path returns nil instead of empty array when in global context.
            if entity.model.active_path.nil? || (entity.model.active_path - path).empty?
              # Active path: entity's path is equal or deeper than active path
              results << transformation
            end
            # Otherwise look if it has siblings, ie. the parent has instances with the same entity.
          else
            instances = (outer.is_a?(Sketchup::ComponentDefinition)) ?
                        outer.instances :
                        (outer.respond_to?(:parent) && outer.parent.respond_to?(:instances)) ? # Sketchup::Drawingelement
                        outer.parent.instances :
                        [] # Sketchup::Model
            instances.each{ |instance|
              queue.push([[instance].concat(path), instance.transformation * transformation])
            }
          end
        end
        return results
      end

      def collect_all_inactive_occurences(entity)
        results = []
        queue = []
        entity_transformation = (entity.respond_to?(:transformation)) ? # Sketchup::ComponentInstance, Sketchup::Group, Sketchup::Image
                                entity.transformation :
                                IDENTITY
        queue.push([[entity], entity_transformation])
        until queue.empty?
          path, transformation = *queue.shift
          outer = path.first
          # If the outermost container is already the model, end the search.
          if outer.parent.is_a?(Sketchup::Model) || outer.parent.nil?
            # Check if this occurence of entity is aside the active path,
            # that means whether the active path branches off the entity's path.
            # Note: Sketchup::Model#active_path returns nil instead of empty array when in global context.
            if entity.model.active_path && !(entity.model.active_path - path).empty?
              # Sibling path: intersection of entity's path and active path is not empty.
              results << transformation
            end
            # Otherwise look if it has siblings, ie. the parent has instances with the same entity.
          else
            instances = (outer.is_a?(Sketchup::ComponentDefinition)) ?
                        outer.instances :
                        (outer.respond_to?(:parent) && outer.parent.respond_to?(:instances)) ? # Sketchup::Drawingelement
                        outer.parent.instances :
                        [] # Sketchup::Model
            instances.each{ |instance|
              queue.push([[instance].concat(path), instance.transformation * transformation])
            }
          end
        end
        return results
      end

    end # class EntityHighlightTool

  end # module ConsolePlugin

end # module AE
