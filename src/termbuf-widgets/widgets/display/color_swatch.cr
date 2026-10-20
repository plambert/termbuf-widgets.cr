require "../../widget"
require "../depth"

module TermBuf::Widgets
  # One color, and what it is.
  #
  #     swatch = ColorSwatch.new Color.rgb(0x3080C0)
  #     swatch.color = Color.indexed(208)
  #
  # The swatch is one row. A bar of cells with the color as their background
  # sits on the left, and the value is written on the right: `#rrggbb` at
  # `Depth::TrueColor`, and `#rrggbb 123` at `Depth::Indexed256` or for an
  # `Indexed` color, where 123 is the index the terminal draws. See
  # `Depth#describe`.
  #
  # The width it is given decides the layout.
  #
  # * At `#narrow` cells or more, the bar and the value sit side by side, and
  #   the bar takes what the value leaves.
  # * Narrower than that, the bar fills the row and the value is written over
  #   it, in black or white by the bar's luminance. See `Depth#ink`.
  # * Narrower than the value itself, the bar is drawn alone.
  #
  # A swatch takes no input and emits nothing. `#color=` changes what the next
  # frame draws.
  class ColorSwatch < Widget
    # Cells between the bar and the value.
    GAP = 1

    # How many colors the swatch shows, and so how it describes one.
    layout_property depth : Depth = Depth::TrueColor

    # The shortest bar drawn beside the value. `#narrow` and
    # `#intrinsic_width` are worked out from it.
    layout_property least_bar : Int32 = 4

    # What the value is written in beside the bar. Over the bar it takes the
    # bar's color behind it and the ink in front.
    property value_style : Style = Style::DEFAULT

    @color : Color

    def initialize(@color : Color,
                   depth : Depth = Depth::TrueColor,
                   least_bar : Int32 = 4,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   style : Style? = nil)
      @depth = depth
      @least_bar = least_bar
      @style = style
      @width = width
      @height = Layout::Sizing.fixed 1
    end

    # The color shown.
    def color : Color
      @color
    end

    # Shows *color* instead. The layout is invalidated only when the value
    # text changes width, since nothing else about the swatch's size depends
    # on the color.
    def color=(color : Color) : Color
      before = value_text.size
      @color = color
      invalidate_layout unless value_text.size == before
      color
    end

    # What is written beside the bar.
    def value_text : String
      @depth.describe @color
    end

    # The color the bar is drawn in, which is what the terminal draws at
    # `#depth`.
    def bar_color : Color
      @depth.shown @color
    end

    # The fewest cells that hold the bar and the value side by side.
    def narrow : Int32
      value_text.size + GAP + @least_bar
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new 1, narrow
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      text = value_text
      if view.width >= narrow
        draw_beside view, text
      else
        draw_bar view, view.width
        draw_over view, text if view.width >= text.size
      end
    end

    private def draw_beside(view : View, text : String) : Nil
      bar = view.width - text.size - GAP
      draw_bar view, bar
      view.write bar + GAP, 0, text, @value_style
    end

    private def draw_bar(view : View, cells : Int32) : Nil
      view.fill Rect.new(0, 0, cells, 1), ' ', Style::DEFAULT.bg(bar_color)
    end

    private def draw_over(view : View, text : String) : Nil
      column = (view.width - text.size) // 2
      view.write column, 0, text, Style::DEFAULT.fg(@depth.ink(@color)).bg(bar_color)
    end
  end
end
