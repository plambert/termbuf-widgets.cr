require "./layout/tree"
require "./widget"

module TermBuf::Widgets
  # Puts a laid-out tree on a drawing surface.
  #
  # One pre-order walk per root in painting order. Every widget gets a `View`
  # cut to its own rectangle, addressed from its own top left, and nested
  # inside a second view cut to whatever its nearest clipping ancestor allows.
  # That second view is the scissor: a widget draws in its own coordinates and
  # whatever reaches past the edge of a scroll panel is trimmed on the way
  # through rather than landing on the panel's neighbours.
  #
  # Styles layer the same way. A widget's `Widget#style` is merged onto the one
  # it inherited and handed to its view, so a panel that names a background
  # gives that background to everything drawn inside it without any of those
  # widgets naming it. A widget's `Widget#wash` goes to the same view, which is
  # what settles every cell it paints against what is already there.
  #
  # The screen is never cleared. A `TermBuf::Commands::Clear` throws away the
  # scroll hints a widget left behind by calling `TermBuf::View#scroll`, and
  # the painter needs those to reach for the terminal's own scrolling instead
  # of rewriting the rows. Each root fills its own rectangle instead, which
  # covers the same cells for a full-screen root and leaves the hints alone.
  module Renderer
    extend self

    # Draws every root of *tree* onto *screen*, lowest first.
    #
    # *images* is where a widget's pictures go. The store is emptied first and
    # filled again as the walk reaches each widget, so what is on screen is
    # what this frame asked for and nothing a previous one left. Without a
    # store no widget is asked, which is what a terminal that draws no
    # pictures gets.
    def render(tree : Layout::Tree, screen : Drawing, images : ImageStore? = nil) : Nil
      images.try &.clear

      tree.roots_in_z_order.each do |root|
        paint root, screen, tree.screen, Style::DEFAULT, true, images
      end
    end

    # Draws one widget and then its children.
    #
    # *clip* is what the nearest clipping ancestor allows, in buffer
    # coordinates, and *inherited* is the style this widget's own is merged
    # onto.
    private def paint(widget : Widget, screen : Drawing, clip : Rect,
                      inherited : Style, root : Bool, images : ImageStore?) : Nil
      return if widget.hidden?

      area = widget.rect.intersect clip
      return if area.empty?

      style = widget.style
      effective = style ? inherited.merge(style) : inherited
      view = scissor(screen, clip).view local(widget.rect, clip), effective, widget.wash
      box = framed widget

      view.fill box if root || style
      widget.border.try &.draw(view, box)
      widget.draw view.view(inside(widget), effective)
      images.try { |store| widget.place_images store, widget.frame }

      inner = clip_for widget, clip
      widget.children.each do |child|
        next if child.floating

        paint child, screen, inner, effective, false, images
      end
    end

    # The box the widget is drawn in, in its own view's coordinates: its
    # rectangle less its margin. The ground is filled and the border drawn
    # around this rather than around the whole rectangle, because a margin is
    # space the widget asked nobody else to use, not space it covers.
    private def framed(widget : Widget) : Rect
      margin = widget.margin
      Rect.new margin.left, margin.top,
        Math.max(0, widget.rect.width - margin.horizontal),
        Math.max(0, widget.rect.height - margin.vertical)
    end

    # A widget's content box in its own view's coordinates: its rectangle less
    # its padding and its border.
    #
    # `#draw` is given this rather than the whole rectangle, because the
    # border was already drawn around it and a widget writing at row zero of
    # its own rectangle would write over the top edge. It is the same box the
    # layout gave the widget's children, so a widget that draws its own
    # content and one that holds children are working in the same coordinates.
    private def inside(widget : Widget) : Rect
      spacing = widget.inset
      content = widget.content

      Rect.new spacing.left, spacing.top, content.width, content.height
    end

    # The surface a widget draws through, cut to what its clipping ancestor
    # allows. Nothing is trimmed twice: the widget's own view sits inside this
    # one and both cuts happen on the way down.
    private def scissor(screen : Drawing, clip : Rect) : View
      screen.view clip
    end

    # *rect* in the scissor's coordinates rather than the buffer's.
    private def local(rect : Rect, clip : Rect) : Rect
      Rect.new rect.x - clip.x, rect.y - clip.y, rect.width, rect.height
    end

    # What this widget's children are allowed: its content box on whichever
    # axes it clips, and whatever it was already given on the others.
    private def clip_for(widget : Widget, clip : Rect) : Rect
      return clip unless widget.clip_x? || widget.clip_y?

      content = widget.content
      box = Rect.new(
        widget.clip_x? ? content.x : clip.x,
        widget.clip_y? ? content.y : clip.y,
        widget.clip_x? ? content.width : clip.width,
        widget.clip_y? ? content.height : clip.height)

      box.intersect clip
    end
  end
end
