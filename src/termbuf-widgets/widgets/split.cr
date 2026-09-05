require "./divider"
require "./panel"

module TermBuf::Widgets
  # Two panes with a rule between them, and the rule can be dragged.
  #
  #     split = Split.new sidebar, body, at: 20
  #
  # The split is a panel holding three things: the first pane, a `Divider`, and
  # the second. How the room is shared is the panes' own sizings, so a split
  # that never moves needs nothing from this class at all — give one pane a
  # fixed size, or both a percent, and the layout does the rest.
  #
  # What this adds is the drag. Moving the rule sets the first pane to a fixed
  # size and the second to grow, which is the only pair of sizings where
  # dragging means what it looks like it means: the pane you sized stays where
  # you put it and the other one takes whatever is left.
  class Split < Panel
    # The pane before the rule.
    getter first : Widget

    # The rule itself.
    getter divider : Divider

    # The pane after it.
    getter second : Widget

    # The fewest cells either pane may be dragged down to.
    #
    # A pane's own sizing minimum is not consulted, because a drag replaces
    # that sizing: this is the floor the split enforces instead.
    property minimum : Int32 = 0

    # Whether the rule is being dragged.
    getter? dragging : Bool = false

    def initialize(@first : Widget, @second : Widget,
                   direction : Layout::Direction = Layout::Direction::Row,
                   at : Int32? = nil,
                   @minimum : Int32 = 0,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow,
                   padding : Layout::Padding = Layout::Padding.all(0),
                   margin : Layout::Padding = Layout::Padding.all(0),
                   border : Border? = nil,
                   style : Style? = nil,
                   divider : Divider? = nil)
      super direction: direction, width: width, height: height, padding: padding,
        margin: margin, border: border, style: style

      @divider = divider || Divider.new
      add @first, @divider, @second
      place at if at
    end

    # Whether the panes sit side by side rather than one above the other.
    def row? : Bool
      direction.row?
    end

    # Cells the panes have to share, the rule's own cell taken off.
    def room : Int32
      box = content
      Math.max((row? ? box.width : box.height) - 1, 0)
    end

    # Where the rule sits, in cells from the start of the content box.
    def at : Int32
      box = content
      row? ? @divider.rect.x - box.x : @divider.rect.y - box.y
    end

    # Puts the rule *position* cells along, held inside what the minimums
    # leave.
    #
    # The first pane is fixed there and the second grows into what is left,
    # which is what makes the rule stay where it was put.
    def place(position : Int32) : Nil
      wanted = Math.max position, @minimum
      # Before the first layout there is no room to hold it inside, and a
      # split built with a starting position must not come out at zero.
      limit = room
      wanted = Math.min wanted, Math.max(limit - @minimum, @minimum) if limit > 0

      if row?
        @first.width = Layout::Sizing.fixed wanted
        @second.width = Layout::Sizing.grow
      else
        @first.height = Layout::Sizing.fixed wanted
        @second.height = Layout::Sizing.grow
      end
    end

    # Picks the rule up, follows the pointer, and lets go.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      case event.action
      in .press?   then pressed event, context
      in .motion?  then dragged event, context
      in .release? then let_go context
      end
    end

    private def pressed(event : Events::Mouse, context : Context) : Nil
      return unless event.button.left?
      return unless @divider.rect.contains? event.x, event.y

      @dragging = true
      context.capture self
      context.consume
    end

    private def dragged(event : Events::Mouse, context : Context) : Nil
      return unless @dragging

      context.consume
      box = content
      place row? ? event.x - box.x : event.y - box.y
    end

    private def let_go(context : Context) : Nil
      return unless @dragging

      @dragging = false
      context.release
      context.consume
    end
  end
end
