require "./panel"

module TermBuf::Widgets
  # A window onto content taller or wider than itself.
  #
  # What makes it a window is clipping: a widget that clips an axis is not a
  # parent its children are compressed to fit, so they keep the size they asked
  # for and the edges do the cutting. The scroll offsets then say which part of
  # them is showing.
  #
  #     panel = Scrollable.new
  #     rows.each { |row| panel.add row }
  #     panel.scroll_to selected
  #
  # A vertical scroll is announced to the surface as well as being drawn, so
  # the painter can reach for the terminal's own scrolling region instead of
  # rewriting every row. See `#draw`.
  class Scrollable < Panel
    # How many cells one notch of the wheel moves.
    property wheel : Int32 = 3

    # The offset the last frame was drawn at, so a frame can say how far the
    # content moved since. Not geometry: nothing about a rectangle depends on
    # it.
    @drawn : Int32 = 0

    def initialize(direction : Layout::Direction = Layout::Direction::Column,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow,
                   padding : Layout::Padding = Layout::Padding.all(0),
                   margin : Layout::Padding = Layout::Padding.all(0),
                   gap : Int32 = 0,
                   align_x : Layout::Align = Layout::Align::Start,
                   align_y : Layout::Align = Layout::Align::Start,
                   border : Border? = nil,
                   style : Style? = nil,
                   clip_x : Bool? = nil,
                   clip_y : Bool? = nil)
      super direction: direction, width: width, height: height, padding: padding,
        margin: margin, gap: gap, align_x: align_x, align_y: align_y,
        border: border, style: style

      # A scrollable column clips top and bottom, a scrollable row left and
      # right. Say so to disagree, which is what a panel scrolling both ways
      # has to do.
      @clip_x = clip_x.nil? ? direction.row? : clip_x
      @clip_y = clip_y.nil? ? direction.column? : clip_y
    end

    # Cells the content comes to, which is what a scrollbar divides the
    # viewport by.
    #
    # Measured from the sizes the children were laid out at rather than from
    # where they were put, because where they were put is where the scroll had
    # them at the last layout and the answer must not move when the scroll
    # does.
    def content_size : {Int32, Int32}
      children = visible_children
      return {0, 0} if children.empty?

      gaps = @gap * (children.size - 1)

      case direction
      in .column? then {children.max_of(&.rect.width), children.sum(&.rect.height) + gaps}
      in .row?    then {children.sum(&.rect.width) + gaps, children.max_of(&.rect.height)}
      end
    end

    # Cells there are to show it in.
    def viewport_size : {Int32, Int32}
      box = content
      {box.width, box.height}
    end

    # The furthest the content can be scrolled before its end is in view.
    def max_scroll : {Int32, Int32}
      size = content_size
      room = viewport_size

      {Math.max(size[0] - room[0], 0), Math.max(size[1] - room[1], 0)}
    end

    # Moves the window by *dx* and *dy*, stopping at either end.
    def scroll_by(dx : Int32 = 0, dy : Int32 = 0) : Nil
      limit = max_scroll
      self.scroll_x = (@scroll_x + dx).clamp(0, limit[0]) if clip_x?
      self.scroll_y = (@scroll_y + dy).clamp(0, limit[1]) if clip_y?
    end

    # Moves the window as little as it takes to bring *widget* into view.
    #
    # A widget larger than the window has its start shown, because a window
    # that cannot hold something is more useful at its beginning than at its
    # end.
    def scroll_to(widget : Widget) : Nil
      offset = offset_of widget
      return unless offset

      reveal offset[0], offset[1], widget.rect.width, widget.rect.height
    end

    # Where *widget* starts within the content, from the content's own origin.
    # `nil` for a widget that is not under this one.
    #
    # Worked out from the sizes of the children in front of it rather than from
    # its rectangle, for the same reason `#content_size` is: a rectangle is
    # where the scroll had it, and the answer has to hold while the scroll
    # changes. A widget deeper than a direct child is placed by the difference
    # between the two rectangles, which the scroll moves together.
    private def offset_of(widget : Widget) : {Int32, Int32}?
      child = direct_child_of widget
      return unless child

      along = 0
      visible_children.each do |candidate|
        break if candidate.same? child

        along += (direction.column? ? candidate.rect.height : candidate.rect.width) + @gap
      end

      base = direction.column? ? {0, along} : {along, 0}
      {base[0] + widget.rect.x - child.rect.x, base[1] + widget.rect.y - child.rect.y}
    end

    # The child of this panel that *widget* sits under, or is.
    private def direct_child_of(widget : Widget) : Widget?
      node : Widget? = widget

      while node
        held = node.parent
        return node if held.try &.same?(self)

        node = held
      end

      nil
    end

    # Moves the window as little as it takes to bring the cells at *left*,
    # *top* into view, measured from the start of the content.
    def reveal(left : Int32, top : Int32, width : Int32 = 1, height : Int32 = 1) : Nil
      limit = max_scroll
      room = viewport_size

      if clip_x?
        wanted = @scroll_x
        wanted = left + width - room[0] if left + width > wanted + room[0]
        wanted = left if left < wanted
        self.scroll_x = wanted.clamp 0, limit[0]
      end

      return unless clip_y?

      wanted = @scroll_y
      wanted = top + height - room[1] if top + height > wanted + room[1]
      wanted = top if top < wanted
      self.scroll_y = wanted.clamp 0, limit[1]
    end

    # Answers a wheel notch, and lets everything else past.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      case event.button
      when .wheel_up?    then scroll_by dy: -@wheel, dx: clip_y? ? 0 : -@wheel
      when .wheel_down?  then scroll_by dy: @wheel, dx: clip_y? ? 0 : @wheel
      when .wheel_left?  then scroll_by dx: -@wheel
      when .wheel_right? then scroll_by dx: @wheel
      else                    return
      end

      context.consume
    end

    # Tells the surface how far the content moved, then leaves the drawing of
    # it to the children.
    #
    # The children are painted over the whole window straight after this, so
    # the scroll is not what puts the cells there. What it is for is the hint
    # it leaves behind: the painter can then send the terminal's own scroll
    # and the rows that came into view, rather than every row in the window.
    # Only the vertical axis, because a terminal scrolls rows and not columns.
    def draw(view : View) : Nil
      moved = @scroll_y - @drawn
      @drawn = @scroll_y
      return if moved.zero? || !clip_y? || view.width <= 0 || view.height <= 0

      view.scroll view.bounds, moved
    end
  end
end
