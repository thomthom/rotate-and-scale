#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
require 'tt_rota-scale.rb'

#-------------------------------------------------------------------------------

module TT::Plugins::RotaScale


  ### MENU & TOOLBARS ### ------------------------------------------------------

  unless file_loaded?( __FILE__ )
    # Menus
    m = UI.menu( 'Tools' )
    m.add_item( PLUGIN_NAME ) { self.scale_3d }
  end


  ### MAIN SCRIPT ### ----------------------------------------------------------

  def self.scale_3d
    my_tool = RotaScale.new
    Sketchup.active_model.select_tool(my_tool)
  end

  class RotaScale

    def initialize
      @cursor_point = nil
      @reference_point1 = nil
      @reference_point2 = nil
      @end_point = nil
      @ctrl = nil

      cursor_rotascale_path = File.join( PATH, 'cursors', 'rotascale.png' )
      @cursor_rotascale_id = UI.create_cursor(cursor_rotascale_path, 14, 13)

      cursor_scale_path = File.join( PATH, 'cursors', 'rotate.png' )
      @cursor_rotate_id = UI.create_cursor(cursor_scale_path, 14, 13)
    end

    def activate
      @cursor_point     = Sketchup::InputPoint.new
      @reference_point1 = Sketchup::InputPoint.new
      @reference_point2 = Sketchup::InputPoint.new
      @end_point        = Sketchup::InputPoint.new

      @drawn = false

      Sketchup::set_status_text 'Pick first point of reference.'

      self.reset(nil)
    end

    def deactivate(view)
      view.invalidate if @drawn
    end

    def onMouseMove(flags, x, y, view)
      if @state == 0
        @cursor_point.pick(view, x, y)
        if @cursor_point != @reference_point1
          view.invalidate if @cursor_point.display? or @reference_point1.display?
          @reference_point1.copy!(@cursor_point)
        end
      elsif @state == 1
        @reference_point2.pick view, x, y, @reference_point1
        #view.tooltip = @reference_point2.tooltip if( @reference_point2.valid? )
        view.invalidate
      else
        @end_point.pick view, x, y, @reference_point1, @reference_point2
        #view.tooltip = @end_point.tooltip if( @end_point.valid? )
        view.invalidate
      end
    end

    def onLButtonDown(flags, x, y, view)

      if @state == 0
        @reference_point1.pick view, x, y
        if @reference_point1.valid?
          @state = 1
          Sketchup::set_status_text('Select second reference point.')
        end
      elsif @state == 1
        @reference_point2.pick view, x, y, @reference_point1
        if @reference_point2.valid?
          @state = 2
          Sketchup::set_status_text('Select third reference point.')
        end
      else
        # create the line on the second click
        if @end_point.valid?

          # Get angle difference
          v1 = @reference_point1.position.vector_to(@reference_point2.position)
          v2 = @reference_point1.position.vector_to(@end_point.position)
          angle = v1.angle_between(v2)

          # Get scale difference
          len1 = @reference_point1.position.distance(@reference_point2.position)
          len2 = @reference_point1.position.distance(@end_point.position)
          scale = len2 / len1

          #puts "p1: #{@reference_point1.position} - p2: #{@reference_point2.position}"
          #puts "len1: #{len1} - len2: #{len2}"
          #puts "Angle: #{angle.radians} - Scale: #{scale}"

          # Model reference variables
          model = Sketchup.active_model

          # Create the scaling transformation
          t_scale = Geom::Transformation.scaling(@reference_point1.position, scale) # 3D
          # This returns a transformation matrix in a format that V-Ray for Sketchup
          # doesn't expect. The whole transformation is scaled down by the scaling factor
          # in the last array value.
          # We work around this by re-creating the transformation scaled to 1.0
          ts = 1.0 / t_scale.to_a[15]
          ta = t_scale.to_a.collect { |d| d * ts }
          t_scale = Geom::Transformation.new(ta)

          # Create the rotation transformation and combine
          # puts "angle: #{angle}"
          # puts "v1: #{v1.inspect}"
          # puts "v2: #{v2.inspect}"
          # puts "v3: #{v3.inspect}"
          v3 = v1 * v2
          if v3.valid? && angle > 0.0
            t_rotation = Geom::Transformation.rotation(@reference_point1.position, v3, angle)
            # Combine both transformations - as long as the user doesn't override it by
            # holding down Ctrl. Then we only rotate.
            t = (@ctrl) ? t_rotation : t_rotation * t_scale
          else
            t = t_scale
            if @ctrl
              self.reset(view)
              return
            end
          end

          #puts "\nTransformation Matrix"
          #puts t.to_a
          #puts 'rotation'
          #puts t_rotation.to_a
          #puts 'scale'
          #puts t_scale.to_a

          model.active_entities.transform_entities(t, model.selection)

          self.reset(view)
        end
      end
      # Clear any inference lock
      view.lock_inference
    end

    # onKeyDown is called when the user presses a key on the keyboard.
    # We are checking it here to see if the user pressed the shift key
    # so that we can do inference locking
    def onKeyDown(key, repeat, flags, view)
      if( key == CONSTRAIN_MODIFIER_KEY && repeat == 1 )
        @shift_down_time = Time.now

        # if we already have an inference lock, then unlock it
        if view.inference_locked?
          # calling lock_inference with no arguments actually unlocks
          view.lock_inference
        elsif @state == 0 && @reference_point1.valid?
          view.lock_inference @reference_point1
        elsif @state == 1 && @reference_point2.valid?
          view.lock_inference @reference_point2, @reference_point1
        elsif @state == 2 && @end_point.valid?
          view.lock_inference @end_point, @reference_point1
        end
      end

      @ctrl = true if key == VK_CONTROL
    end

    # onKeyUp is called when the user releases the key
    # We use this to unlock the interence
    # If the user holds down the shift key for more than 1/2 second, then we
    # unlock the inference on the release.  Otherwise, the user presses shift
    # once to lock and a second time to unlock.
    def onKeyUp(key, repeat, flags, view)
      if( key == CONSTRAIN_MODIFIER_KEY &&
        view.inference_locked? &&
        (Time.now - @shift_down_time) > 0.5 )
        view.lock_inference
      end

      @ctrl = false if key == VK_CONTROL
    end

    def draw(view)
      # (!) Thicker lines upon inference lock
      # (!) Different line for the reference
      # (!) UI feedback to scale and rotation

      if @reference_point1.valid?
        if @reference_point1.display?
          @reference_point1.draw(view)
          @drawn = true
        end

        if @reference_point2.valid?
          @reference_point2.draw(view) if @reference_point2.display?

          view.line_width = 3.0 if view.inference_locked?
          view.set_color_from_line(@reference_point1, @reference_point2)
          self.draw_geometry(@reference_point1.position, @reference_point2.position, view)
          @drawn = true
        end

        if @end_point.valid?
          @end_point.draw(view) if @end_point.display?

          view.line_width = 1.0
          view.set_color_from_line(@reference_point1, @reference_point2)
          self.draw_geometry(@reference_point1.position, @reference_point2.position, view)

          view.line_width = 3.0 if view.inference_locked?
          view.set_color_from_line(@reference_point1, @end_point)
          self.draw_geometry(@reference_point1.position, @end_point.position, view)

          # -- Info text --
          # Get angle difference
          v1 = @reference_point1.position.vector_to(@reference_point2.position)
          v2 = @reference_point1.position.vector_to(@end_point.position)
          angle = v1.angle_between(v2)

          # Get scale difference
          len1 = @reference_point1.position.distance(@reference_point2.position)
          len2 = @reference_point1.position.distance(@end_point.position)
          scale = len2 / len1

          screen_xy = view.screen_coords(@reference_point1.position)
          #view.draw_text(screen_xy, "Angle: #{angle.radians.round_to(1)}° - Scale: #{scale.round_to(3)}")
          view.draw_text(screen_xy, "Angle: #{PLUGIN.round_to(angle.radians,1)}° - Scale: #{PLUGIN.round_to(scale,3)}")

          @drawn = true
        end
      end
    end

    # Draw the geometry
    def draw_geometry(pt1, pt2, view)
      view.draw_line(pt1, pt2)
    end

    def onSetCursor
      if @ctrl
        UI.set_cursor(@cursor_rotate_id)
      else
        UI.set_cursor(@cursor_rotascale_id)
      end
    end

    # Reset the tool back to its initial state
    def reset(view)
      # This variable keeps track of which point we are currently getting
      @state = 0

      # clear the InputPoints
      @reference_point1.clear
      @reference_point2.clear
      @end_point.clear

      if view
        view.tooltip = nil
        view.invalidate if @drawn
      end

      @drawn = false
      @ctrl = false
    end
  end


  ### HELPER METHODS ### -------------------------------------------------------

  def self.round_to(number, precision)
    (number*10**precision).round.to_f/10**precision
  end

  module Helping_Hand
    def self.start_operation(name)
      model = Sketchup.active_model
      # Make use of the SU7 speed boost with start_operation while
      # making sure it works in SU6.
      if Sketchup.version.split('.')[0].to_i >= 7
        model.start_operation(name, true)
      else
        model.start_operation(name)
      end
    end
  end # module Helping_Hand


  ### DEBUG ### ----------------------------------------------------------------

  # @note Debug method to reload the plugin.
  #
  # @example
  #   TT::Plugins::RotaScale.reload
  #
  # @return [Integer] Number of files reloaded.
  # @since 1.0.0
  def self.reload
    original_verbose = $VERBOSE
    $VERBOSE = nil
    # Core file (this)
    load __FILE__
    # Supporting files
    if defined?( PATH ) && File.exist?( PATH )
      x = Dir.glob( File.join(PATH, '*.{rb,rbs}') ).each { |file|
        load file
      }
      x.length + 1
    else
      1
    end
  ensure
    $VERBOSE = original_verbose
  end

end # module

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------
