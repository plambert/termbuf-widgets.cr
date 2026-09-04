require "../widget"
require "./errors"

module TermBuf::Widgets::Layout
  # A widget tree and the screen it is laid out against.
  #
  # The tree holds the one bit of state the widgets do not: whether the
  # rectangles they carry are still good. Any `Widget#layout_property` setter
  # marks it dirty, and `#layout_if_needed` is what a frame calls before
  # drawing.
  #
  #     tree = Layout::Tree.new root, Rect.full(columns, rows)
  #     tree.layout_if_needed
  #     root.each_in_tree { |widget| widget.draw screen.view(widget.rect) }
  class Tree
    # The widget the screen is given to.
    getter root : Widget

    # Widgets lifted out of the flow, in the order they are laid out and
    # painted: declaration order, and a float declared inside another float's
    # subtree after the float that hosts it, so nesting resolves without a
    # sort.
    #
    # Rebuilt by every `#layout`, which is what keeps it right through an
    # `Widget#add` or a `Widget#remove` that the setter never sees.
    getter floats = [] of Widget

    # How grapheme clusters are measured, which is what text measurement is
    # done against.
    property policy : Unicode::WidthPolicy

    # The rectangle the root is laid out into.
    getter screen : Rect

    # Whether the rectangles are stale.
    getter? dirty : Bool = true

    # Whether `#layout_if_needed` checks a clean tree by laying it out again
    # and comparing.
    #
    # A missed `#invalidate` shows up as a frame drawn from last frame's
    # rectangles, which is the kind of bug that looks like a redraw problem
    # for a day. Turn this on in specs and in development builds and it
    # becomes a `MissedInvalidation` at the point the bad frame would have
    # been drawn. It doubles the cost of every clean frame, so leave it off in
    # production.
    class_property? verify_invalidation : Bool = false

    def initialize(@root : Widget,
                   @screen : Rect = Rect.new(0, 0, 0, 0),
                   @policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT)
      @root.tree = self
    end

    # Points the tree at a different root, which is then the one that gets the
    # screen.
    def root=(root : Widget) : Widget
      return root if root.same? @root

      @root.tree = nil
      @root = root
      root.tree = self
      invalidate
      root
    end

    # Lays the tree out against a different rectangle.
    def screen=(screen : Rect) : Rect
      return screen if screen == @screen

      @screen = screen
      invalidate
      screen
    end

    # Marks the rectangles stale.
    def invalidate : Nil
      @dirty = true
    end

    # Lays the tree out against *screen*, whether or not anything changed.
    def layout(screen : Rect = @screen) : Nil
      @screen = screen
      collect_floats
      Engine.run self
      @dirty = false
    end

    # The roots painting order goes through: the tree itself, then every float
    # by its `Layout::Floating#z`, lowest first, ties keeping declaration
    # order.
    def roots_in_z_order : Array(Widget)
      ordered = @floats.map_with_index { |float, index| {float, index} }
      ordered.sort! do |a, b|
        first = a[0].floating.try(&.z) || 0
        second = b[0].floating.try(&.z) || 0
        first == second ? a[1] <=> b[1] : first <=> second
      end

      roots = [@root] of Widget
      ordered.each { |pair| roots << pair[0] }
      roots
    end

    # The deepest visible widget at (*x*, *y*), or `nil` when nothing is there.
    #
    # Roots are tried from the top of the painting order down, so a float takes
    # a point over whatever it covers. A float declared `capture: false` is
    # passed through as though it were not there, which is what a tooltip
    # wants: it is drawn over the thing it describes but does not take its
    # clicks.
    def hit(x : Int32, y : Int32) : Widget?
      roots_in_z_order.reverse_each do |candidate|
        floating = candidate.floating
        next if floating && !floating.capture?

        if found = candidate.at x, y
          return found
        end
      end

      nil
    end

    # Whether *widget* is still somewhere under the root.
    def holds?(widget : Widget) : Bool
      widget.under? @root
    end

    # Finds every float, in the order pass 7 lays them out.
    private def collect_floats : Nil
      @floats.clear
      gather @root

      index = 0
      while index < @floats.size
        gather @floats[index]
        index += 1
      end
    end

    # Adds every float directly under *widget*, without descending into one:
    # a float's own subtree is walked later, from the list, so a nested float
    # lands after the float that hosts it.
    private def gather(widget : Widget) : Nil
      widget.children.each do |child|
        next if child.hidden?

        if child.floating
          @floats << child
        else
          gather child
        end
      end
    end

    # Lays the tree out if anything has changed since the last one.
    #
    # With `.verify_invalidation` on, a clean tree is laid out anyway and the
    # result compared against what it already held; a difference means
    # something changed geometry behind the setters' backs, and raises
    # `MissedInvalidation`.
    def layout_if_needed : Nil
      if @dirty
        layout
        return
      end

      return unless Tree.verify_invalidation?

      before = {} of Widget => Rect
      @root.each_in_tree { |widget| before[widget] = widget.rect }
      Engine.run self
      verify before
    end

    private def verify(before : Hash(Widget, Rect)) : Nil
      @root.each_in_tree do |widget|
        was = before[widget]?
        next if was == widget.rect

        raise MissedInvalidation.new build_message(widget, was)
      end
    end

    private def build_message(widget : Widget, was : Rect?) : String
      String.build do |message|
        message << "layout of " << widget.class << " changed without the tree being invalidated: "
        if was
          message << was << " became " << widget.rect
        else
          message << "it was not in the tree when the last layout ran"
        end
      end
    end
  end
end
