require "../widget"
require "./border"

module TermBuf::Widgets
  # A widget that is only somewhere to put other widgets.
  #
  # `Widget` is abstract because nearly every widget draws something. This is
  # the one that does not: it holds children, carries a style and a border, and
  # leaves the rest to the layout and the renderer. Rows, columns, panes and
  # the root of an application are all this.
  #
  #     root = Panel.new direction: :column, width: Layout::Sizing.grow,
  #       height: Layout::Sizing.grow, padding: Layout::Padding.all(1)
  #     root.add header, body, footer
  class Panel < Widget
    def initialize(direction : Layout::Direction = Layout::Direction::Column,
                   width : Layout::Sizing = Layout::Sizing.fit,
                   height : Layout::Sizing = Layout::Sizing.fit,
                   padding : Layout::Padding = Layout::Padding.all(0),
                   gap : Int32 = 0,
                   align_x : Layout::Align = Layout::Align::Start,
                   align_y : Layout::Align = Layout::Align::Start,
                   border : Border? = nil,
                   style : Style? = nil)
      @direction = direction
      @width = width
      @height = height
      @padding = padding
      @gap = gap
      @align_x = align_x
      @align_y = align_y
      @border = border
      @style = style
    end
  end
end
