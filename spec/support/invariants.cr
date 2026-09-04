module Fixtures
  # What a laid-out tree has to look like, whatever shape it turned out to be.
  #
  # Each check answers a description of the first thing it found wrong, or
  # `nil` when it found nothing, so a property failure names the widget and the
  # numbers rather than just failing.
  module Invariants
    extend self

    alias Layout = TermBuf::Widgets::Layout
    alias Widget = TermBuf::Widgets::Widget
    alias Axis = TermBuf::Widgets::Layout::Axis

    # Every invariant, over every visible widget in *tree*.
    def check(tree : Layout::Tree) : String?
      overflowed = false
      failure = nil

      walk tree.root do |widget|
        next if failure

        overflowed ||= overflows? widget
        failure = check_widget widget
      end

      return failure if failure
      return if overflowed

      check_screen tree
    end

    # Yields every visible widget, parents first, skipping a hidden subtree
    # whose rectangles nothing has any reason to keep up to date.
    def walk(widget : Widget, &block : Widget ->) : Nil
      return if widget.hidden?

      block.call widget
      widget.children.each { |child| walk child, &block }
    end

    # Every rectangle in the tree, in walk order.
    def rects(tree : Layout::Tree) : Array(TermBuf::Rect)
      found = [] of TermBuf::Rect
      walk(tree.root) { |widget| found << widget.rect }
      found
    end

    private def check_widget(widget : Widget) : String?
      children = widget.visible_children
      return if children.empty?

      main = main_axis widget
      content = widget.content

      check_cross(widget, children, content, cross_axis(main)) ||
        check_disjoint(widget, children) ||
        check_main(widget, children, content, main) ||
        check_order(widget, children, content, main) ||
        check_percent(widget, children, content, main)
    end

    # Nothing overflows across the stacking axis: the content box is a hard
    # ceiling there, and alignment never pushes a child past either edge.
    private def check_cross(widget : Widget, children : Array(Widget),
                            content : TermBuf::Rect, axis : Axis) : String?
      room = extent content, axis
      start = origin content, axis

      children.each do |child|
        size = extent child.rect, axis
        at = origin child.rect, axis

        return describe(widget, child, "is #{size} across #{axis} in a content box of #{room}") if size > room
        return describe(widget, child, "starts at #{at} across #{axis}, before #{start}") if at < start
        if at + size > start + room
          return describe(widget, child, "ends at #{at + size} across #{axis}, past #{start + room}")
        end
      end

      nil
    end

    # No two siblings cover the same cell.
    private def check_disjoint(widget : Widget, children : Array(Widget)) : String?
      children.each_with_index do |child, index|
        next if child.rect.empty?

        children.each(within: index + 1..) do |other|
          next if other.rect.empty?
          next if child.rect.intersect(other.rect).empty?

          return describe widget, child, "overlaps a sibling at #{child.rect.intersect(other.rect)}"
        end
      end

      nil
    end

    # Along the stacking axis the children fit, unless what they insist on will
    # not; and a grower with no ceiling leaves nothing behind.
    #
    # What a child insists on is its minimum, except for a percent child: its
    # share is of the whole content box rather than of what its siblings left,
    # and nothing shrinks it afterwards, so what it took is what it demands.
    private def check_main(widget : Widget, children : Array(Widget),
                           content : TermBuf::Rect, axis : Axis) : String?
      room = extent content, axis
      gaps = gap_total widget, children.size
      used = children.sum { |child| extent child.rect, axis } + gaps
      demanded = children.sum { |child| insisted child, axis } + gaps

      if used > room && demanded <= room
        return describe widget, nil, "overflows #{axis} by #{used - room} with room for the #{demanded} its children insist on in #{room}"
      end

      unbounded = children.any? do |child|
        sizing = sizing_of child, axis
        sizing.grow? && sizing.max == Int32::MAX && sizing.weight > 0
      end

      if unbounded && used < room
        return describe widget, nil, "left #{room - used} of #{axis} unclaimed with a grower that has no ceiling"
      end

      nil
    end

    # The children run along the axis in order, from the content origin or
    # after it, each one the gap past the last.
    private def check_order(widget : Widget, children : Array(Widget),
                            content : TermBuf::Rect, axis : Axis) : String?
      cursor = nil.as(Int32?)

      children.each_with_index do |child, index|
        at = origin child.rect, axis

        if cursor.nil?
          return describe(widget, child, "starts at #{at} along #{axis}, before #{origin content, axis}") if at < origin content, axis
        elsif at != cursor
          return describe widget, child, "starts at #{at} along #{axis}, not at #{cursor} where child #{index - 1} left off"
        end

        cursor = at + extent(child.rect, axis) + widget.gap
      end

      nil
    end

    # Every percent child took the share the boundary formula gives it,
    # whenever no bound of its own got in the way.
    private def check_percent(widget : Widget, children : Array(Widget),
                              content : TermBuf::Rect, axis : Axis) : String?
      shares = children.select { |child| sizing_of(child, axis).percent? }
      return if shares.empty?

      base = Math.max 0, extent(content, axis) - gap_total(widget, children.size)
      cumulative = 0
      previous = 0
      expected = shares.map do |child|
        cumulative += sizing_of(child, axis).weight
        boundary = (cumulative * base + 50) // 100
        size = boundary - previous
        previous = boundary
        size
      end

      shares.each_with_index do |child, index|
        sizing = sizing_of child, axis
        # A share held back by a bound of its own is the apportionment spec's
        # business; here only the unclamped arithmetic is under test.
        next if expected[index] < minimum(child, axis) || expected[index] > sizing.max

        actual = extent child.rect, axis
        next if actual == expected[index]

        return describe widget, child, "took #{actual} of #{axis} where #{sizing.weight}% of #{base} is #{expected[index]}"
      end

      nil
    end

    # Nothing landed off the screen, in a tree where nothing overflowed.
    private def check_screen(tree : Layout::Tree) : String?
      screen = tree.screen
      failure = nil

      walk tree.root do |widget|
        next if failure
        next if screen.contains? widget.rect

        failure = "#{widget.class} at #{widget.rect} is outside the screen #{screen}"
      end

      failure
    end

    private def insisted(widget : Widget, axis : Axis) : Int32
      return extent widget.rect, axis if sizing_of(widget, axis).percent?

      minimum widget, axis
    end

    private def overflows?(widget : Widget) : Bool
      children = widget.visible_children
      return false if children.empty?

      axis = main_axis widget
      used = children.sum { |child| extent child.rect, axis } + gap_total(widget, children.size)
      used > extent widget.content, axis
    end

    private def describe(widget : Widget, child : Widget?, complaint : String) : String
      String.build do |message|
        message << widget.class << ' ' << widget.rect
        message << " child " << child.class << ' ' << child.rect if child
        message << ": " << complaint
      end
    end

    private def main_axis(widget : Widget) : Axis
      case widget.direction
      in .row?    then Axis::X
      in .column? then Axis::Y
      end
    end

    private def cross_axis(axis : Axis) : Axis
      case axis
      in .x? then Axis::Y
      in .y? then Axis::X
      end
    end

    private def extent(rect : TermBuf::Rect, axis : Axis) : Int32
      case axis
      in .x? then rect.width
      in .y? then rect.height
      end
    end

    private def origin(rect : TermBuf::Rect, axis : Axis) : Int32
      case axis
      in .x? then rect.x
      in .y? then rect.y
      end
    end

    private def sizing_of(widget : Widget, axis : Axis) : Layout::Sizing
      case axis
      in .x? then widget.width
      in .y? then widget.height
      end
    end

    private def minimum(widget : Widget, axis : Axis) : Int32
      case axis
      in .x? then widget.min_width
      in .y? then widget.min_height
      end
    end

    private def gap_total(widget : Widget, count : Int32) : Int32
      count > 1 ? widget.gap * (count - 1) : 0
    end
  end
end
