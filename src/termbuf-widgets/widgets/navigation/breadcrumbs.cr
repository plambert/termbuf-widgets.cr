require "../../message"
require "../../router"
require "../../widget"
require "../input/interactive"
require "./links"

module TermBuf::Widgets
  # The path to where you are, one crumb per step, joined by a separator.
  #
  #     crumbs = Breadcrumbs.new %w[home projects termbuf]
  #     crumbs.crumbs.first.uri = "file:///home"
  #
  # A click on a crumb says `Selected`, and a crumb given a *uri* is also
  # written as an OSC 8 hyperlink, so a terminal that draws those makes it
  # clickable on its own account as well. A terminal that does not draws the
  # text and nothing else: the link is interned either way and the encoder
  # emits nothing for it without `TermBuf::Capability::Osc8Links`.
  #
  # ### Running out of room
  #
  # The last crumb is where you are, so it is the one that is kept: crumbs are
  # given up from the left, and what is left starts with an ellipsis to say
  # that something was. Only when the last crumb alone will not fit is it cut,
  # which is the point at which there is nothing better to do.
  #
  # Like a `NavigationBar`, this draws its own crumbs rather than holding a
  # `Label` each. Which crumbs are given up is a decision about the whole row,
  # and the layout engine apportions space between children without ever asking
  # one to leave.
  class Breadcrumbs < Widget
    include Interactive

    # A crumb was clicked.
    struct Selected < Message
      # The trail it happened on, since one handler usually answers several.
      getter crumbs : Breadcrumbs

      # Which crumb it was, counting from zero.
      getter index : Int32

      # The crumb itself.
      getter crumb : Crumb

      def initialize(@crumbs : Breadcrumbs, @index : Int32, @crumb : Crumb)
      end
    end

    # One step of the path.
    class Crumb
      # What the crumb says.
      property label : String

      # Where it points, for a terminal that draws hyperlinks, or `nil` for a
      # crumb that is only clickable through this widget.
      property uri : String?

      def initialize(@label : String, @uri : String? = nil)
      end
    end

    # Where one crumb was drawn, in buffer coordinates.
    record Span, index : Int32, x : Int32, width : Int32 do
      # Whether column *x* falls on this crumb.
      def holds?(x : Int32) : Bool
        @x <= x < @x + @width
      end
    end

    # What crumbs are joined by on a terminal that measures it at one cell.
    SEPARATOR = "›"

    # What stands in for it where it does not come out at one cell.
    SEPARATOR_ASCII = ">"

    # What says crumbs were given up, on a terminal that measures it at one
    # cell.
    ELLIPSIS = "…"

    # What stands in for it where it does not.
    ELLIPSIS_ASCII = "..."

    # The crumbs, first step first.
    getter crumbs = [] of Crumb

    # What the crumbs are joined by, or `nil` to choose it from the width
    # policy the tree was built with.
    layout_property separator : String? = nil

    # What a crumb that is not the last is drawn in.
    property crumb_style : Style = Style::DEFAULT

    # What the last crumb — where you are — is drawn in.
    property current_style : Style = Style::DEFAULT.bold

    # What the separators and the leading ellipsis are drawn in.
    property separator_style : Style = Style::DEFAULT.faint

    @spans = [] of Span

    def initialize(labels : Enumerable(String) = [] of String,
                   separator : String? = nil,
                   style : Style? = nil)
      @separator = separator
      @style = style
      @width = Layout::Sizing.grow
      @height = Layout::Sizing.fit
      labels.each { |label| @crumbs << Crumb.new(label) }
    end

    # ----------------------------------------------------------- crumbs

    # Adds a crumb at the end and answers it.
    def add(label : String, uri : String? = nil) : Crumb
      crumb = Crumb.new label, uri
      @crumbs << crumb
      invalidate_layout
      crumb
    end

    # Replaces the whole trail.
    def path=(labels : Enumerable(String)) : Array(Crumb)
      @crumbs.clear
      labels.each { |label| @crumbs << Crumb.new(label) }
      invalidate_layout
      @crumbs
    end

    # Takes the crumbs after *index* off, which is what following a crumb
    # does to the trail behind it.
    def truncate(index : Int32) : Nil
      return unless 0 <= index < @crumbs.size - 1

      @crumbs.delete_at (index + 1)..
      invalidate_layout
    end

    # ------------------------------------------------------------ input

    # The crumb drawn at (*x*, *y*) in buffer coordinates, as the last frame
    # drew it, or `nil` when the point is not on one.
    def crumb_at(x : Int32, y : Int32) : Int32?
      box = content
      return unless y == box.y

      @spans.find(&.holds?(x)).try &.index
    end

    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      clicked event, context do
        index = crumb_at event.x, event.y
        emit Selected.new self, index, @crumbs[index] if index
      end
    end

    # -------------------------------------------------------- measuring

    # What the crumbs are joined by under *policy*.
    def separator_for(policy : Unicode::WidthPolicy) : String
      told = @separator
      return told if told

      Glyphs.single_cell?({SEPARATOR}, policy) ? SEPARATOR : SEPARATOR_ASCII
    end

    # What says crumbs were given up, under *policy*.
    def ellipsis_for(policy : Unicode::WidthPolicy) : String
      Glyphs.single_cell?({ELLIPSIS}, policy) ? ELLIPSIS : ELLIPSIS_ASCII
    end

    # The first crumb shown at *width*, which is zero for a trail that fits
    # whole and higher for one cut from the left.
    #
    # The answer is the smallest start that fits, so as much of the path is
    # kept as there is room for. A start above zero costs the leading ellipsis
    # and the separator after it.
    def start_for(width : Int32, policy : Unicode::WidthPolicy) : Int32
      last = @crumbs.size - 1
      return 0 if last < 0

      (0..last).each do |start|
        return start if row_width(start, policy) <= width
      end

      last
    end

    # How wide the row comes out starting at *start*.
    private def row_width(start : Int32, policy : Unicode::WidthPolicy) : Int32
      joiner = " #{separator_for policy} "
      between = Unicode.string_width joiner, policy
      used = start.zero? ? 0 : Unicode.string_width(ellipsis_for(policy), policy) + between

      (start..(@crumbs.size - 1)).each_with_index do |index, place|
        used += between if place > 0
        used += Unicode.string_width @crumbs[index].label, policy
      end

      used
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      last = @crumbs.last?
      return Layout::Intrinsic.new 0, 0 unless last

      # The last crumb is the one that is kept whole, so it is what the trail
      # needs; everything in front of it can go.
      Layout::Intrinsic.new Unicode.string_width(last.label, policy), row_width(0, policy)
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @crumbs.empty? ? 0 : 1
    end

    # ---------------------------------------------------------- drawing

    def draw(view : View) : Nil
      @spans.clear
      return if @crumbs.empty? || view.width <= 0 || view.height <= 0

      joiner = " #{separator_for view.policy} "
      start = start_for view.width, view.policy
      column = 0

      # The leading mark says crumbs were given up, and it is worth a cell only
      # while what is left still fits. Below that the last crumb is all there
      # is room for, and it gets the row to itself.
      if !start.zero? && row_width(start, view.policy) <= view.width
        column += write view, column, ellipsis_for(view.policy), @separator_style
        column += write view, column, joiner, @separator_style
      end

      (start..(@crumbs.size - 1)).each do |index|
        column += write view, column, joiner, @separator_style if index > start
        column += draw_crumb view, column, index
      end
    end

    # Writes one crumb and answers how many columns it took.
    private def draw_crumb(view : View, column : Int32, index : Int32) : Int32
      crumb = @crumbs[index]
      last = index == @crumbs.size - 1
      paint = last ? @current_style : @crumb_style

      uri = crumb.uri
      paint = paint.linked Linking.link_id(view, uri) if uri

      width = write view, column, crumb.label, paint
      box = content
      @spans << Span.new(index, box.x + column, width)
      width
    end

    # Writes *text*, cut at the right edge, and answers how many columns of
    # the view it took.
    private def write(view : View, column : Int32, text : String, paint : Style) : Int32
      room = Math.max view.width - column, 0
      shown = Unicode.ellipsize text, room, ellipsis_for(view.policy), view.policy
      view.write column, 0, shown, paint
      Unicode.string_width shown, view.policy
    end
  end
end
