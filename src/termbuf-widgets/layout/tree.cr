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

    # Widgets lifted out of the flow, laid out against the screen rather than
    # against a parent. Not resolved yet.
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
      Engine.run self
      @dirty = false
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
