require "../widget"
require "./scrollable"

module TermBuf::Widgets
  # Where a `Scrollable` has got to, and a handle for moving it.
  #
  # One cell thick and as long as there is room, like a `Divider`, because
  # that is what a scrollbar is. It draws a track with a thumb on it whose
  # length is the share of the content that is showing and whose position is
  # how far down that share sits.
  #
  #     bar = Scrollbar.new panel
  #     row.add panel, bar
  #
  # A press on the track pages towards it, a press on the thumb picks it up,
  # and a wheel notch is handed to the panel so that the bar answers the wheel
  # the same way the content does.
  class Scrollbar < Widget
    # Which way the bar runs.
    enum Orientation
      # Down the side of something that scrolls vertically.
      Vertical

      # Along the bottom of something that scrolls sideways.
      Horizontal
    end

    # The panel this bar shows the position of, or `nil` for one attached to
    # nothing, which draws an empty track.
    property target : Scrollable?

    # Which way the bar runs, or `nil` to take it from what the panel clips.
    layout_property orientation : Orientation? = nil

    # What the part of the bar with no thumb on it is drawn with.
    property track : Char = '│'

    # :ditto: for a bar that runs across.
    property track_across : Char = '─'

    # What the thumb is drawn with.
    property thumb : Char = '█'

    # What the thumb is drawn in, or `nil` to take the bar's own style.
    property thumb_style : Style? = nil

    # Where in the thumb it was picked up, or `nil` when nothing is dragging.
    @grab : Int32? = nil

    def initialize(@target : Scrollable? = nil,
                   orientation : Orientation? = nil,
                   style : Style? = nil)
      @orientation = orientation
      @style = style
    end

    # Which way this bar actually runs: what it was told, or whichever axis
    # its panel clips, or down.
    def runs : Orientation
      told = @orientation
      return told if told

      held = @target
      return Orientation::Vertical if held.nil? || held.clip_y? || !held.clip_x?

      Orientation::Horizontal
    end

    # Whether the bar runs down rather than across.
    def vertical? : Bool
      runs.vertical?
    end

    # One cell thick and as long as there is room.
    def width : Layout::Sizing
      vertical? ? Layout::Sizing.fixed(1) : Layout::Sizing.grow
    end

    # :ditto:
    def height : Layout::Sizing
      vertical? ? Layout::Sizing.grow : Layout::Sizing.fixed(1)
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.exact 1
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      1
    end

    # Cells the bar is long.
    def length : Int32
      box = content
      vertical? ? box.height : box.width
    end

    # Cells of content, cells of window, and how far in the window sits.
    private def measures : {Int32, Int32, Int32}
      held = @target
      return {0, 0, 0} unless held

      axis = vertical? ? 1 : 0
      scroll = vertical? ? held.scroll_y : held.scroll_x

      {held.content_size[axis], held.viewport_size[axis], scroll}
    end

    # How many cells of thumb there are: the share of the content that is
    # showing, and never less than one, because a thumb nobody can see is not
    # a thumb.
    def thumb_size : Int32
      size, room, _ = measures
      return length if size <= 0 || room <= 0 || size <= room

      Math.max (room * length) // size, 1
    end

    # How far along the bar the thumb starts.
    def thumb_start : Int32
      size, room, scroll = measures
      furthest = size - room
      travel = length - thumb_size
      return 0 if furthest <= 0 || travel <= 0

      ((scroll * travel) + furthest // 2) // furthest
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      view.fill view.bounds, vertical? ? @track : @track_across
      return if thumb_size <= 0

      view.fill thumb_box, @thumb, @thumb_style || Style::DEFAULT
    end

    # The thumb's own cells, in the bar's coordinates.
    private def thumb_box : Rect
      start = thumb_start.clamp 0, Math.max(length - thumb_size, 0)

      if vertical?
        Rect.new 0, start, 1, Math.min(thumb_size, Math.max(length - start, 0))
      else
        Rect.new start, 0, Math.min(thumb_size, Math.max(length - start, 0)), 1
      end
    end

    # A press picks the thumb up or pages towards where it was pressed; a
    # motion while it is held moves the panel; a release lets go.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      held = @target
      return unless held
      return held.handle event, context if wheel? event

      case event.action
      in .press?   then pressed held, at(event), context
      in .motion?  then dragged held, at(event), context
      in .release? then let_go context
      end
    end

    private def wheel?(event : Events::Mouse) : Bool
      button = event.button
      button.wheel_up? || button.wheel_down? || button.wheel_left? || button.wheel_right?
    end

    # Where along the bar the pointer is.
    private def at(event : Events::Mouse) : Int32
      box = content
      vertical? ? event.y - box.y : event.x - box.x
    end

    private def pressed(held : Scrollable, position : Int32, context : Context) : Nil
      context.consume
      start = thumb_start

      if position < start
        page held, -1
      elsif position >= start + thumb_size
        page held, 1
      else
        @grab = position - start
        context.capture self
      end
    end

    private def dragged(held : Scrollable, position : Int32, context : Context) : Nil
      grab = @grab
      return unless grab

      context.consume
      size, room, _ = measures
      furthest = size - room
      travel = length - thumb_size
      return if furthest <= 0 || travel <= 0

      wanted = ((position - grab) * furthest + travel // 2) // travel
      move held, wanted.clamp(0, furthest)
    end

    private def let_go(context : Context) : Nil
      return unless @grab

      @grab = nil
      context.release
      context.consume
    end

    # One window's worth, towards *direction*.
    private def page(held : Scrollable, direction : Int32) : Nil
      _, room, _ = measures
      step = Math.max(room, 1) * direction

      vertical? ? held.scroll_by(dy: step) : held.scroll_by(dx: step)
    end

    private def move(held : Scrollable, to : Int32) : Nil
      if vertical?
        held.scroll_by dy: to - held.scroll_y
      else
        held.scroll_by dx: to - held.scroll_x
      end
    end
  end
end
