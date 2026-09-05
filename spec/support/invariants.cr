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

      failure ||= check_floats tree
      return failure if failure
      return if overflowed

      check_screen tree
    end

    # Every float sits inside the screen, unless it is larger than the screen,
    # in which case it sits at the edge and the view cuts it. And the painting
    # order is the root, then the floats by z, lowest first.
    def check_floats(tree : Layout::Tree) : String?
      screen = tree.screen

      tree.floats.each do |float|
        if failure = check_placed(float, screen, Axis::X) || check_placed(float, screen, Axis::Y)
          return failure
        end
      end

      check_z_order tree
    end

    # Whatever `Layout::Tree#hit` answers for a point covers that point, is
    # visible, and is not a float that declined to capture.
    def check_hits(tree : Layout::Tree, random : Random) : String?
      screen = tree.screen
      return if screen.empty?

      12.times do
        x = random.rand screen.x..(screen.x + screen.width - 1)
        y = random.rand screen.y..(screen.y + screen.height - 1)
        found = tree.hit x, y
        next unless found

        return "#{found.class} at #{found.rect} was hit at #{x},#{y}" unless found.rect.contains? x, y
        return "hidden #{found.class} was hit at #{x},#{y}" if found.hidden?
      end

      nil
    end

    private def check_placed(float : Widget, screen : TermBuf::Rect, axis : Axis) : String?
      start = origin screen, axis
      at = origin float.rect, axis
      size = extent float.rect, axis
      room = extent screen, axis

      return "#{float.class} at #{float.rect} starts before the screen #{screen} on #{axis}" if at < start
      return if at + size <= start + room
      return if size > room && at == start

      "#{float.class} at #{float.rect} runs past the screen #{screen} on #{axis} with room to slide back"
    end

    private def check_z_order(tree : Layout::Tree) : String?
      roots = tree.roots_in_z_order
      return "the painting order does not start with the root" unless roots.first?.try &.same?(tree.root)

      if roots.size != tree.floats.size + 1
        return "the painting order holds #{roots.size} roots for #{tree.floats.size} floats"
      end

      previous = nil.as(Int32?)
      roots.each_with_index do |candidate, index|
        next if index.zero?

        depth = candidate.floating.try(&.z) || 0
        return "the painting order puts z #{depth} after z #{previous}" if previous && depth < previous

        previous = depth
      end

      nil
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
    # What a child insists on is its minimum, except for a percent child:
    # nothing shrinks its share afterwards, so what it took is what it
    # demands.
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
    #
    # The base is the content box less the gaps and less the siblings already
    # settled at a size, which is what a percent is a percent of. A `Fit`
    # sibling is one of those, and its settled size is the one it was measured
    # at; a row with no room left shrinks it afterwards, and there is then no
    # way to read that size back off the tree. `#squeezed?` is where that is
    # given up on.
    private def check_percent(widget : Widget, children : Array(Widget),
                              content : TermBuf::Rect, axis : Axis) : String?
      shares = children.select { |child| sizing_of(child, axis).percent? }
      return if shares.empty?
      return if squeezed? widget, children, content, axis

      base = percent_base children, extent(content, axis) - gap_total(widget, children.size), axis
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

    # What the percents were percents of: *room*, the content box less the
    # gaps, less every sibling settled at a size before the shares were worked
    # out.
    private def percent_base(children : Array(Widget), room : Int32, axis : Axis) : Int32
      settled = children.sum do |child|
        sizing = sizing_of child, axis
        sizing.fixed? || sizing.fit? ? extent(child.rect, axis) : 0
      end

      Math.max 0, room - settled
    end

    # Whether a `Fit` child of *widget* may have been shrunk after the percent
    # shares were handed out, which is the one case where the size it is
    # carrying now is not the size the shares were worked out against.
    #
    # Shrinking runs only when the children come to more than the box holds,
    # and it leaves them filling it or overflowing it, so a box with room to
    # spare cannot have been through it.
    private def squeezed?(widget : Widget, children : Array(Widget),
                          content : TermBuf::Rect, axis : Axis) : Bool
      return false unless children.any? { |child| sizing_of(child, axis).fit? }

      used = children.sum { |child| extent child.rect, axis } + gap_total(widget, children.size)
      used >= extent content, axis
    end

    # Nothing in the flow landed off the screen, in a tree where nothing
    # overflowed. Floats are placed against the screen rather than laid out in
    # it, and `#check_floats` is what holds them to it.
    private def check_screen(tree : Layout::Tree) : String?
      screen = tree.screen
      failure = nil

      walk_flow tree.root do |widget|
        next if failure
        next if screen.contains? widget.rect

        failure = "#{widget.class} at #{widget.rect} is outside the screen #{screen}"
      end

      failure
    end

    # Yields every visible widget laid out in the flow, stopping at a float.
    private def walk_flow(widget : Widget, &block : Widget ->) : Nil
      return if widget.hidden?

      block.call widget
      widget.visible_children.each { |child| walk_flow child, &block }
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
