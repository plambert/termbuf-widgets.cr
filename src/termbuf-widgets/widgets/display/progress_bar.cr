require "../../widget"

module TermBuf::Widgets
  # How far along something is, drawn as a filled run and an empty one.
  #
  #     bar = ProgressBar.new
  #     bar.value = 0.4
  #     bar.label = ProgressBar::Placement::Centre
  #
  # The bar is one row tall and grows to whatever width it is given. `#value`
  # is a fraction from zero to one, clamped, and how many cells that fills is
  # worked out at draw time from the width the layout settled on — so the same
  # bar in a narrower panel simply fills fewer cells, with no relayout and
  # nothing cached to go stale.
  #
  # Nothing here reads the value to decide how wide the bar wants to be, which
  # is what lets `#value=` skip `Widget#invalidate_layout` altogether. A
  # percentage never runs past four cells, so the label costs no width either.
  #
  # ### Colour
  #
  # `#filled_style` and `#empty_style` are the flat answer. For a ramp across
  # the filled run, hand `#blend` a `TermBuf::Gradient#background`:
  #
  #     ramp = TermBuf::Gradient.new Color.rgb(0x2060C0), Color.rgb(0xC02020),
  #       bar.rect, :horizontal
  #     bar.blend = ramp.background
  #
  # A blend on a draw call is asked in the **buffer's** coordinates, not the
  # widget's, so a gradient meant to span the bar is built against the
  # rectangle the layout gave it. `nil` is no blend at all, which is the
  # default and costs nothing.
  #
  # ### Indeterminate
  #
  # With `#indeterminate?` set the bar draws a block of `#block_width` cells
  # sliding between the two edges, at `#phase` of the way across. Nothing here
  # advances the phase: this shard owns no timers, so whatever is driving the
  # frames steps it.
  #
  #     bar.phase = (elapsed.total_seconds % 2.0) / 2.0
  class ProgressBar < Widget
    # Where the label sits, or that there is none.
    #
    # Named for the placement rather than for the label, because `Label` is
    # already a widget in this namespace and a nested enum of that name would
    # hide it inside this class.
    enum Placement
      # No label.
      None

      # In the middle of the bar.
      Centre

      # Against the right edge.
      End
    end

    # The cell a filled column is drawn with.
    property filled_char : Char = '█'

    # The cell an empty column is drawn with.
    property empty_char : Char = ' '

    # What the filled run is drawn in.
    property filled_style : Style = Style::DEFAULT

    # What the empty run is drawn in.
    property empty_style : Style = Style::DEFAULT.faint

    # Run for every filled cell, or `nil` for none. See the class docs.
    property blend : Blend? = nil

    # Where the label sits.
    property label : Placement = Placement::None

    # What the label says, or `nil` for the percentage.
    property label_text : String? = nil

    # What the label is drawn in. It is written with
    # `TermBuf::Style::KEEP_BACKGROUND`, so it keeps whatever colour the bar
    # put behind it and a gradient shows through.
    property label_style : Style = Style::DEFAULT.bold

    # Whether the bar has a fraction to show, or only that work is going on.
    property? indeterminate : Bool = false

    # How far the sliding block has travelled, from zero at the left edge to
    # one at the right. Only read when `#indeterminate?`.
    property phase : Float64 = 0.0

    # Cells the sliding block is wide. Only read when `#indeterminate?`.
    property block_width : Int32 = 4

    # The width the bar asks for when nothing else has an opinion. A `Grow`
    # bar never uses it; a `Fit` one is this wide.
    layout_property preferred_width : Int32 = 20

    @value : Float64 = 0.0

    def initialize(value : Float64 = 0.0,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   filled_style : Style = Style::DEFAULT,
                   empty_style : Style = Style::DEFAULT.faint,
                   label : Placement = Placement::None,
                   blend : Blend? = nil,
                   style : Style? = nil)
      @value = value.clamp 0.0, 1.0
      @filled_style = filled_style
      @empty_style = empty_style
      @label = label
      @blend = blend
      @style = style
      @width = width
      @height = Layout::Sizing.fixed 1
    end

    # How far along, from zero to one.
    def value : Float64
      @value
    end

    # Sets how far along, holding it inside zero and one.
    #
    # No invalidation: nothing about the layout is worked out from the value,
    # and the next frame draws the whole tree anyway.
    def value=(value : Float64) : Float64
      @value = value.clamp 0.0, 1.0
    end

    # :ditto:
    def value=(value : Number) : Float64
      self.value = value.to_f
    end

    # Cells filled in a bar *width* across.
    #
    # Rounded away from zero at a half, rather than to the even neighbour the
    # way `Float#round` does on its own: half of ten cells is five whichever
    # half it is, and a bar that fills two cells at a quarter and three at
    # three quarters is a bar nobody trusts.
    def filled_cells(width : Int32) : Int32
      return 0 if width <= 0

      (width * @value).round(:ties_away).to_i.clamp 0, width
    end

    # Where the sliding block starts in a bar *width* across, and how wide it
    # is there: a block wider than the bar is cut to it.
    def block_at(width : Int32) : {Int32, Int32}
      return {0, 0} if width <= 0

      cells = @block_width.clamp 1, width
      room = width - cells

      {(room * @phase.clamp(0.0, 1.0)).round(:ties_away).to_i.clamp(0, room), cells}
    end

    # What the label says: `#label_text`, or the percentage when there is
    # none.
    def label_of : String
      text = @label_text
      return text if text

      "#{(@value * 100).round.to_i}%"
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new 1, Math.max(@preferred_width, 1)
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      @indeterminate ? draw_block(view) : draw_fraction(view)
      draw_label view
    end

    private def draw_fraction(view : View) : Nil
      filled = filled_cells view.width
      fill view, 0, filled, @filled_char, @filled_style, @blend
      fill view, filled, view.width - filled, @empty_char, @empty_style, nil
    end

    private def draw_block(view : View) : Nil
      start, cells = block_at view.width

      fill view, 0, view.width, @empty_char, @empty_style, nil
      fill view, start, cells, @filled_char, @filled_style, @blend
    end

    private def fill(view : View, start : Int32, cells : Int32, char : Char,
                     style : Style, blend : Blend?) : Nil
      return if cells <= 0

      view.fill Rect.new(start, 0, cells, 1), char, style, blend
    end

    # Writes the label over the bar, keeping the colour already behind it.
    private def draw_label(view : View) : Nil
      column = case @label
               in .none?   then nil
               in .centre? then (view.width - width_of(view)) // 2
               in .end?    then view.width - width_of(view)
               end

      return unless column && column >= 0

      view.write column, 0, label_of, @label_style, blend: Style::KEEP_BACKGROUND
    end

    private def width_of(view : View) : Int32
      Unicode.string_width label_of, view.policy
    end
  end
end
