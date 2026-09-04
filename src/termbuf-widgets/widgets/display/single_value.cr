require "../../widget"

module TermBuf::Widgets
  # One number, made prominent, with a caption under it.
  #
  #     cell = SingleValue.new 94.2, caption: "cpu"
  #     cell.format = ->(amount : Float64) { "%.1f%%" % amount }
  #     cell.thresholds = [{0.0, green}, {70.0, amber}, {90.0, red}]
  #
  # The tile is as wide as the wider of its two rows and one row tall for the
  # value plus another for the caption. In less room than that both rows are
  # cut and marked with `#ellipsis`, so a tile in a column that got squeezed
  # says something rather than nothing.
  #
  # ### Colour
  #
  # `#colour` is asked first when it is set: a block from the value to a
  # `TermBuf::Style` covers whatever thresholds cannot. Failing that
  # `#thresholds` is walked, and the style of the highest bound at or below
  # the value wins — so a list is read as "from here up, this colour". A value
  # under every bound takes `#value_style`, which is also what an empty list
  # leaves everything at.
  class SingleValue < Widget
    # A bound and what a value at or above it is drawn in.
    alias Threshold = {Float64, Style}

    # The number the tile is about.
    layout_property value : Float64 = 0.0

    # What sits under the value, or `nil` for none.
    layout_property caption : String? = nil

    # Which side of the tile the two rows sit on.
    layout_property align : Unicode::Align = Unicode::Align::Left

    # What marks a row cut short, or `nil` to cut it unmarked.
    layout_property ellipsis : String? = "…"

    # What the value is drawn in when no threshold and no block says
    # otherwise.
    property value_style : Style = Style::DEFAULT.bold

    # What the caption is drawn in.
    property caption_style : Style = Style::DEFAULT.faint

    # Bounds and the styles they turn the value. See the class docs.
    property thresholds = [] of Threshold

    # What decides the value's colour, ahead of `#thresholds`, or `nil` for
    # none. Colour changes nothing about the geometry, so setting one costs no
    # layout.
    property colour : Proc(Float64, Style)? = nil

    @format : Proc(Float64, String)? = nil

    def initialize(value : Number = 0.0,
                   caption : String? = nil,
                   align : Unicode::Align = Unicode::Align::Left,
                   value_style : Style = Style::DEFAULT.bold,
                   caption_style : Style = Style::DEFAULT.faint,
                   ellipsis : String? = "…",
                   style : Style? = nil)
      @value = value.to_f
      @caption = caption
      @align = align
      @value_style = value_style
      @caption_style = caption_style
      @ellipsis = ellipsis
      @style = style
    end

    # Sets the number the tile is about, from anything that is one.
    def value=(value : Number) : Float64
      self.value = value.to_f
    end

    # How the value is turned into text, or `nil` for `Float64#to_s`.
    def format : Proc(Float64, String)?
      @format
    end

    # Sets how the value is turned into text.
    #
    # Always an invalidation: a formatter is a closure, and two of them that
    # compare equal can still produce different widths, so there is nothing
    # here worth checking before saying so.
    def format=(format : Proc(Float64, String)?) : Proc(Float64, String)?
      @format = format
      invalidate_layout
      format
    end

    # The value as it is shown.
    def text : String
      formatter = @format
      formatter ? formatter.call(@value) : @value.to_s
    end

    # What the value is drawn in, once the block and the thresholds have had
    # their say.
    def style_of_value : Style
      block = @colour
      return block.call(@value) if block

      found = @value_style
      @thresholds.each { |bound, style| found = style if @value >= bound }
      found
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      widest = Unicode.string_width text, policy
      if below = @caption
        widest = Math.max widest, Unicode.string_width(below, policy)
      end

      Layout::Intrinsic.new Math.min(widest, 1), widest
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @caption ? 2 : 1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      row view, 0, text, style_of_value
      below = @caption
      row view, 1, below, @caption_style if below && view.height > 1
    end

    private def row(view : View, index : Int32, text : String, style : Style) : Nil
      return if text.empty?

      marker = @ellipsis
      shown = Unicode.ellipsize text, view.width, marker || "", view.policy
      return if shown.empty?

      view.write column_for(shown, view), index, shown, style
    end

    # Where a row starts, given the room left over on it.
    private def column_for(text : String, view : View) : Int32
      room = view.width - Unicode.string_width(text, view.policy)
      return 0 if room <= 0

      case @align
      in .left?   then 0
      in .right?  then room
      in .center? then room // 2
      end
    end
  end
end
