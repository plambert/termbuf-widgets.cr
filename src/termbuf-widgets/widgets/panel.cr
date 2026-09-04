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
    # A picture drawn across the panel, or `nil` for none.
    #
    # Nothing is decoded or scaled here: the terminal is handed the bytes and
    # the cells to draw them across. A terminal that draws no pictures gets
    # nothing sent, so a panel can carry one unconditionally.
    property image : Image? = nil

    # Where the picture sits against the text. Negative is under it, which is
    # what a background wants: the cells keep their glyphs and the picture
    # shows through wherever they are blank. Zero and above is over the text.
    property image_z : Int32 = -1

    def initialize(direction : Layout::Direction = Layout::Direction::Column,
                   width : Layout::Sizing = Layout::Sizing.fit,
                   height : Layout::Sizing = Layout::Sizing.fit,
                   padding : Layout::Padding = Layout::Padding.all(0),
                   margin : Layout::Padding = Layout::Padding.all(0),
                   gap : Int32 = 0,
                   align_x : Layout::Align = Layout::Align::Start,
                   align_y : Layout::Align = Layout::Align::Start,
                   border : Border? = nil,
                   style : Style? = nil,
                   @image : Image? = nil,
                   @image_z : Int32 = -1)
      @direction = direction
      @width = width
      @height = height
      @padding = padding
      @margin = margin
      @gap = gap
      @align_x = align_x
      @align_y = align_y
      @border = border
      @style = style
    end

    # Puts the panel's picture across the box it draws in.
    def place_images(store : ImageStore, frame : Rect) : Nil
      picture = @image
      return if picture.nil? || frame.empty?

      store.place picture, frame, @image_z
    end
  end
end
