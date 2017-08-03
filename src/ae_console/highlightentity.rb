module AE


  class Console


    class DrawEntity


# Note: Sketchup entity vertices expose an unexpected behavior depending on the
# active context. When the active context is equal or deeper than the entity's
# context, `position` gives the global coordinates instead of the local coordinates.
# This tool however recursively adds up group/component transformations to convert
# local coordinates into global coordinates. The issue has no impact because in 
# the above described situation Sketchup also returns identity transformations.


      @@last_point = ORIGIN


      def initialize(model=nil)
        @model              = (model.is_a?(Sketchup::Model)) ? model : Sketchup.active_model
        @entity             = nil
        @transformations_active    = []
        # Color for elements in the active path.
        @color_active       = @model.rendering_options["HighlightColor"]
        @color_active_transparent = Sketchup::Color.new(@color_active) # transparent for polygons
        @color_active_transparent.alpha = 0.5
        # Color for elements in sibling paths, like entities in other instances of a component.
        # In SketchUp, the so-called "components in the rest of the model"
        @color_rest         = Sketchup::Color.new(@color_active)
        @color_rest.alpha   = 0.25
        @color_rest_transparent = Sketchup::Color.new(@color_rest) # transparent for polygons
        @color_rest_transparent.alpha = 0.05
      end


      def select(entity)
        if (entity.is_a?(Sketchup::Drawingelement) ||
            entity.is_a?(Sketchup::Curve)) && entity.model || entity.is_a?(Sketchup::Vertex) ||
            entity.is_a?(Geom::Point3d) || entity.is_a?(Geom::Vector3d) || entity.is_a?(Geom::BoundingBox)
          @entity = entity
        else
          return @entity = nil
        end

        # Find all occurences of the entity (in instances) and collect their transformations.
        @transformations_active = []
        @transformations_rest   = []

        if @entity.is_a?(Sketchup::Drawingelement) || @entity.is_a?(Sketchup::Vertex)
          collect_all_occurences(@entity)
        else
          # Point3d, Vector3d, Geom::BoundingBox have no instance path (no position in
          # model nesting hierarchy). So we draw them always relative to the active context.
          @transformations_active << @model.edit_transform
        end
        @model.active_view.invalidate
      end


      def deactivate(view)
        view.invalidate
      end


      def draw(view)
        # Drawing settings
        color = @color_active
        color_transparent = @color_active_transparent
        view.drawing_color = color
        view.line_width    = 5

        # Point3d / Vertex
        case @entity
        when Geom::Point3d, Sketchup::Vertex
          p1                 = (@entity.is_a?(Sketchup::Vertex)) ? @entity.position : @entity
          view.line_width    = 3
          view.drawing_color = @color_active
          @transformations_active.each { |t| draw_point3d(view, p1, t) }
          view.drawing_color = @color_rest
          @transformations_rest.each { |t| draw_point3d(view, p1, t) } # We only have transformations here for vertices.
          @@last_point = p1

          # Vector3d
        when Geom::Vector3d
          return unless @entity.valid?
          draw_vector3d(view, @@last_point, @entity, @color_active, @transformations_active.first)

          # Edge
        when Sketchup::Edge, Sketchup::Curve, Sketchup::ArcCurve
          @transformations_active.each{ |t| draw_edges(view, @entity, @color_active, t) }
          @transformations_rest.each{ |t| draw_edges(view, @entity, @color_rest, t) }

          # Face
        when Sketchup::Face
          @transformations_active.each{ |t| draw_face(view, @entity, @color_active, @color_active_transparent, t) }
          @transformations_rest.each{ |t| draw_face(view, @entity, @color_rest, @color_rest_transparent, t) }

          # Group / Component / Image / Definition / BoundingBox
        when Sketchup::Group, Sketchup::ComponentInstance, Sketchup::Image, Sketchup::ComponentDefinition,
            Geom::BoundingBox
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
          color = @color_active
          color_transparent  = @color_active_transparent
          @transformations_active.each { |t| draw_bounds(view, bounds, color, color_transparent, t) }
          color = @color_rest
          color_transparent = @color_rest_transparent
          @transformations_rest.each { |t| draw_bounds(view, bounds, color, color_transparent, t) }

          # Other. For entities with undefined shape, draw a circle around them.
          # Include texts with leader (in 3d space), but not texts without leader because they use screen space.
        else
          if @entity.is_a?(Sketchup::Drawingelement) && !(@entity.is_a?(Sketchup::Text) && !@entity.has_leader?)
            center = @entity.bounds.center
            # Diameter; consider a minimum for Drawingelements that have no diameter
            diameter = [@entity.bounds.diagonal/2.0, view.pixels_to_model(5, cp)].max
            @transformations_active.each { |t| draw_circle(center, diameter, @color_active, t) }
            @transformations_rest.each { |t| draw_circle(center, diameter, @color_rest, t) }
          end
        end
      end


      private


      def collect_all_occurences(entity)
        # Depth search of all transformations of all occurences of @entity (within nested component instances).
        # This depth search starts from the leaves (!) and multiplies the local transformations up to the root.
        # The initial leaf is @entity. For all containers encountered on the way to the root (containing @entity),
        # their instances are added as further leaves.
        queue = []
        entity_transformation = (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group) ||
            entity.is_a?(Sketchup::Image)) ? entity.transformation : Geom::Transformation.new
        queue.push([[entity], entity_transformation])
        until queue.empty?
          path, transformation = *queue.shift
          outer = path.first
          # If the outermost container is already the model, end the search.
          if outer.parent.is_a?(Sketchup::Model) || outer.parent.nil?
            # Check if this occurence of @entity is in the active path.
            if @model.active_path && !(@model.active_path - path).empty?
              # Sibling path: intersection of entity's path and active path is not empty.
              # Sketchup::Model#active_path returns nil instead of empty array when in global context.
              @transformations_rest << transformation
            else
              # Active path: entity's path is equal or deeper than active path
              @transformations_active << transformation
            end
            # Otherwise look if it has siblings, ie. the parent has instances with the same entity.
          else
            instances = (outer.is_a?(Sketchup::ComponentDefinition)) ? outer.instances :
                (outer.respond_to?(:parent) && outer.parent.respond_to?(:instances)) ? outer.parent.instances : []
            instances.each{ |instance|
              queue.push([[instance].concat(path), instance.transformation * transformation])
            }
          end
        end
      end


      def draw_edges(view, entity, line_color, t=IDENTITY)
        points = entity.vertices.map { |v| view.screen_coords(v.position.transform(t)) }
        view.drawing_color = line_color
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


      def draw_point3d(view, point, color, t=IDENTITY)
        view.drawing_color = color
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
      def draw_vector3d(view, p, vector, color, t=IDENTITY)
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
        view.drawing_color = color
        view.draw2d(GL_LINE_STRIP, p1, p2)
        # Draw an arrow at the end of the vector.
        vec.length = 9 # pixels
        side       = vec * Z_AXIS
        arrow      = [p2, p2-vec-vec+side, p2-vec-vec-side]
        view.draw2d(GL_POLYGON, arrow)
      end


      def draw_bounds(view, bounds, line_color, face_color, t=IDENTITY)
        view.drawing_color = line_color
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


    end # class DrawEntity


# Extension for highlighting SketchUp entities and Point3d
    class HighlightEntity < DrawEntity

      # Since SketchUp used to crash when reverting to the previous tool (pop_tool)
      # if there was no previous tool, we keep track of the tool stack length.
      # It seems my current installations of SU2013, SU8, SU7.1 return true/false
      # instead of the last tool (according to API), and do not crash.
      # This tool works only on one model.
      @@tool_stack_length ||= 1
      @@instance          ||= nil
      @@model             ||= nil

      # Change the tool (for being able to draw at the screen)
      # and highlight the entity with given object_id.
      # @param [Sketchup::Entity,Geom::BoundingBox] entity
      def self.entity(entity)
        raise ArgumentError unless entity.is_a?(Sketchup::Entity) && entity.valid? || entity.is_a?(Geom::BoundingBox)
        @@model = (entity.respond_to?(:model)) ? entity.model || Sketchup.active_model : Sketchup.active_model
        # Get an instance of this tool and highlight the entity.
        @@model.tools.push_tool(@@instance || @@instance = self.new)
        @@instance.select(entity)
        @@tool_stack_length += 1
      end


      # Change the tool (for being able to draw at the screen)
      # and highlight the given Point.
      # @param [Numeric] x
      # @param [Numeric] y
      # @param [Numeric] z
      def self.point(x, y, z)
        raise ArgumentError unless [x, y, z].all? { |n| n.is_a?(Numeric) }
        point   = Geom::Point3d.new(x, y, z)
        @@model = Sketchup.active_model
        @@model.tools.push_tool(@@instance || @@instance = self.new)
        @@instance.select(point)
        @@tool_stack_length += 1
      end


      # Change the tool (for being able to draw at the screen)
      # and highlight the given Vector.
      # @param [Numeric] x
      # @param [Numeric] y
      # @param [Numeric] z
      def self.vector(x, y, z)
        raise ArgumentError unless [x, y, z].all? { |n| n.is_a?(Numeric) }
        vector = Geom::Vector3d.new(x, y, z)
        raise ArgumentError.new('Invalid zero-length vector') unless vector.valid?
        @@model = Sketchup.active_model
        @@model.tools.push_tool(@@instance || @@instance = self.new)
        @@instance.select(vector)
        @@tool_stack_length += 1
      end


      # Change the tool back.
      def self.stop
        if @@tool_stack_length > 1
          # Be careful, this can crash SketchUp when removing the only tool on the stack.
          @@model.tools.pop_tool
          @@tool_stack_length -= 1
        end
      end


      # Instance methods:

      #def draw(view)
      #  if AE::Console.ctrl? && ( @entity.is_a?(Geom::Point3d) || @entity.is_a?(Geom::Vector3d) || @entity.is_a?(Geom::BoundingBox) )
      #    # Override to draw in 2d
      #  else
      #    super(view)
      #  end
      #end
=begin
  def draw_point3d(view, p, t)
    p = view.screen_coords(p.transform(t)) unless AE::Console.ctrl?
    # Round it to pixels.
    p.x = p.x.to_i; p.y = p.y.to_i; p.z = p.z.to_i
    # Draw a cross with radius r.
    r = 3
    view.draw2d(GL_LINES, p + [r,r,0], p + [-r,-r,0], p + [r,-r,0], p + [-r,r,0])
  end

  def draw_vector3d(view, p1, p2, t=IDENTITY)
    p1 = view.screen_coords(p1.transform(t)) unless AE::Console.ctrl?
    p2 = view.screen_coords(p2.transform(t)) unless AE::Console.ctrl?
    p1.z = p2.z = 0
    vec = p1.vector_to(p2)
    # If the last viewed point is out of the viewport, take the viewport center.
    w = view.vpwidth
    h = view.vpheight
    if p1.x < 0 || p1.x > w || p1.y < 0 || p1.y > h
      p1 = Geom::Point3d.new(w/2, h/2, 0)
      p2 = p1 + vec
    end
    p2 = Geom.intersect_line_line([p1, vec], [[0,0,0], Y_AXIS]) || p2 if p2.x < 0
    p2 = Geom.intersect_line_line([p1, vec], [[w,0,0], Y_AXIS]) || p2 if p2.x > w
    p2 = Geom.intersect_line_line([p1, vec], [[0,0,0], X_AXIS]) || p2 if p2.y < 0
    p2 = Geom.intersect_line_line([p1, vec], [[0,h,0], X_AXIS]) || p2 if p2.y > h
    # Draw the vector direction.
    view.draw2d(GL_LINE_STRIP, p1, p2)
    # Draw an arrow at the end of the vector.
    vec.length = -9
    side = vec * Z_AXIS
    arrow = [p2, p2+vec+vec+side, p2+vec+vec+side.reverse]
    view.draw2d(GL_POLYGON, arrow)
  end

  def draw_bounds(view, bounds, color, color_t, t=IDENTITY)
    view.drawing_color = color
    ps = (0..7).map{ |i| bounds.corner(i).transform!(t) }
    # A quad strip around the bounding box
    ps1 = [ ps[0],ps[4],  ps[1],ps[5],  ps[3],ps[7],  ps[2],ps[6],  ps[0],ps[4] ]
    # Two quads not covered by the quad strip
    ps2 = [ ps[0],ps[1],  ps[3],ps[2] ]  # bottom
    ps3 =  [ ps[4],ps[5],  ps[7],ps[6] ] # top
    # Quad strips ps1, ps2, ps3 can be interpreted as lines, but these are missing:
    ps4 = [ ps[0],ps[2],  ps[1],ps[3] ]
    ps5 = [ ps[4],ps[6],  ps[5],ps[7] ]
    # Draw lines
    if AE::Console.ctrl?
      view.draw2d(GL_LINES, [ps2, ps4].flatten)
    else
      view.draw2d(GL_LINES, [ps1, ps2, ps3, ps4, ps5].flatten.map{ |p| view.screen_coords(p) })
    end
    # Draw polygons
    if Sketchup.version.to_i >= 8 # support of transparent color
      view.drawing_color = color_t
      if AE::Console.ctrl?
        view.draw2d(GL_QUADS, ps2)
      else
        view.draw(GL_QUAD_STRIP, ps1)
        view.draw(GL_QUADS, [ps2, ps3].flatten)
      end
    end
  end
=end
      # This is because we want to draw onto the screen only when the cursor hovers the WebDialog. [optional]
      def onMouseMove(flags, x, y, view)
        self.class.stop
      end

    end # class HighlightEntity


    class SelectEntity < DrawEntity

      if Sketchup.version.to_i >= 16
        if RUBY_PLATFORM =~ /darwin/
          IMG_CURSOR_SELECT_ENTITY = File.join(DIR, 'images', 'cursor_select_entity.pdf')
        else
          IMG_CURSOR_SELECT_ENTITY = File.join(DIR, 'images', 'cursor_select_entity.svg')
        end
      else
        IMG_CURSOR_SELECT_ENTITY = File.join(DIR, 'images', 'cursor_select_entity.png')
      end

      # We select this tool only temporarily over the current tool and then switch back.
      # Since SketchUp used to crash when reverting to the previous tool (pop_tool)
      # if there was no previous tool, we keep track of the tool stack length.
      # It seems my current installations of SU2013, SU8, SU7.1 return true/false
      # instead of the last tool (according to API), and do not crash.
      # This tool works in a multi-document interface.
      @@tool_stack_length ||= Hash.new(1)
      @@active_instances  ||= []


      def self.select_tool(*args, &block)
        model    = Sketchup.active_model
        instance = self.new(*args, &block)
        model.tools.push_tool(instance)
        @@tool_stack_length[model] += 1
      end


      def self.deselect_tool
        @@active_instances.each { |instance| instance.deselect_tool }
      end


      def deselect_tool
        if @@tool_stack_length[@model] > 1
          # Be careful, this can crash SketchUp when removing the only tool on the stack.
          success = @model.tools.pop_tool
          # pop_tool calls already deactivate
        end
      end


      def activate
        @@active_instances << self
        Sketchup.status_text = TRANSLATE["Click to select an entity. Right-click to abort. Press the ctrl key to select points. Press the shift key to use inferencing."]
      end


      def deactivate(view)
        @@active_instances.delete(self)
        @@tool_stack_length[@model] -= 1 if @@tool_stack_length[@model] > 1
        super
      end


      def initialize(name=nil, binding=nil, &block)
        @model    = Sketchup.active_model
        @callback = block if block_given?
        @ctrl     = false
        @shift    = false
        @name     = name if name.is_a?(String) && name[/^[^\!\"\'\`\@\$\%\|\&\/\(\)\[\]\{\}\,\;\?\<\>\=\+\-\*\/\#\~\\]+$/]
        @binding  = (binding.is_a?(Binding)) ? binding : TOPLEVEL_BINDING
        @cursor   = UI::create_cursor(IMG_CURSOR_SELECT_ENTITY, 10, 10)
        @ip       = Sketchup::InputPoint.new
        super()
      end


      def onSetCursor
        UI.set_cursor(@cursor)
      end


      def onLButtonDown(flags, x, y, view)
        pick_entity_or_point(view, x, y)
        return if @entity.nil?
        # Create a unique name for the reference if no desired name was given.
        if @name.is_a?(String) && @name[/^[^\!\"\'\`\@\$\%\|\&\/\(\)\[\]\{\}\,\;\?\<\>\=\+\-\*\/\#\~\\]+$/]
          name = @name
        else
          name = suggested_name = case @entity
            # Short names: (You can add more)
          when Sketchup::ComponentInstance
            "component"
          when Geom::Point3d
            "p"
            # Or generic name:
          else
            @entity.respond_to?(:typename) ?
                @entity.typename.downcase :
                @entity.class.to_s[/[^\:]+$/].downcase
          end
          i    = 0
          name = "#{suggested_name}#{i+=1}" while AE::Console.unnested_eval("defined?(#{name})", @binding) && @entity != AE::Console.unnested_eval("#{name}", @binding)
        end
        # Assign the entity to that reference and return the reference as a string.
        id = @entity.object_id
        AE::Console.unnested_eval("#{name} = ObjectSpace._id2ref(#{id})", @binding)
        @callback.call(name) if @callback.is_a?(Proc)
        # Deselect this tool.
        deselect_tool
      end


      def getMenu(menu)
        deselect_tool
      end


      def onRButtonDown(flags, x, y, view)
        deselect_tool
      end


      def onMouseMove(flags, x, y, view)
        pick_entity_or_point(view, x, y)
      end


      def onKeyDown(key, repeat, flags, view)
        @ctrl  = true if key == COPY_MODIFIER_KEY # VK_CONTROL
        @shift = true if key == CONSTRAIN_MODIFIER_KEY # VK_SHIFT
      end


      def onKeyUp(key, repeat, flags, view)
        @ctrl  = false if key == COPY_MODIFIER_KEY # VK_CONTROL
        @shift = false if key == CONSTRAIN_MODIFIER_KEY # VK_SHIFT
      end


      def pick_entity_or_point(view, x, y)
        # Get point/inference under cursor.
        if @ctrl || AE::Console.ctrl?
          # With inferencing: use InputPoint
          if @shift || AE::Console.shift?
            @ip.pick(view, x, y)
            return unless @ip.valid?
            point = @ip.position.transform(@model.edit_transform.inverse)
            # Without inferencing: use a raytest
          else
            ray    = view.pickray(x, y)
            result = @model.raytest(ray)
            return unless result
            point = result[0].transform(@model.edit_transform.inverse)
          end
          select(point)

          # Get an entity is under the cursor.
        else
          # With inferencing: use InputPoint
          if @shift || AE::Console.shift?
            @ip.pick(view, x, y)
            return unless @ip.valid?
            entity = @ip.edge || @ip.face
            # Without inferencing: use PickHelper
          else
            pick_helper = view.pick_helper
            pick_helper.do_pick(x, y)
            entity = pick_helper.best_picked
            entity = entity.curve if entity.is_a?(Sketchup::Edge) && entity.curve
          end
          select(entity)
        end
      end

    end


  end # class Console


end # module AE
