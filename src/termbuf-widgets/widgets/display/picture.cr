require "../../widget"
require "./readout"

module TermBuf::Widgets
  # A picture drawn over the cells it is given, with words for the terminals
  # that cannot draw one.
  #
  #     shot = Picture.new Image.png(path), columns: 40, rows: 12,
  #       alt: "the graph"
  #
  # Named `Picture` rather than `Image` because `TermBuf::Image` is the thing
  # it holds: a widget of that name would hide it from every other widget in
  # this namespace, `Panel#image` included.
  #
  # ### Size
  #
  # *columns* and *rows* fix the box, and leaving either out lets it grow to
  # whatever the layout has spare. Nothing is decoded or scaled here — the
  # pixels go to the terminal along with the number of cells to draw them
  # across, and the terminal does the scaling. That is the whole of `#place`.
  #
  # ### When there is no picture
  #
  # `#alt` is drawn in the box, every frame, whether or not the terminal draws
  # pictures. On one that does, the picture is put over those cells afterwards
  # and covers them; on one that does not, the words are what is left. That is
  # cheaper and steadier than asking whether pictures work and drawing one
  # thing or the other, because the answer is not known where `Widget#draw`
  # runs — the store reaches the widget one call later, in `#place_images`.
  #
  # It also means a picture placed *under* the text with a negative `#z` shows
  # its alt text over itself, so leave `#alt` empty for one of those. See
  # `TermBuf::Placement#z`.
  class Picture < Widget
    # The pixels, or `nil` for a widget holding none yet.
    property image : Image? = nil

    # What is written in the box for a terminal that draws no pictures, or
    # empty for nothing at all.
    layout_property alt : String = ""

    # Which side of the box the alt text sits on.
    layout_property align : Unicode::Align = Unicode::Align::Center

    # Where the picture sits against the text. See `TermBuf::Placement#z`.
    property z : Int32 = 0

    def initialize(@image : Image? = nil,
                   columns : Int32? = nil,
                   rows : Int32? = nil,
                   alt : String = "",
                   align : Unicode::Align = Unicode::Align::Center,
                   z : Int32 = 0,
                   style : Style? = nil)
      @alt = alt
      @align = align
      @z = z
      @style = style
      @width = columns ? Layout::Sizing.fixed(columns) : Layout::Sizing.grow
      @height = rows ? Layout::Sizing.fixed(rows) : Layout::Sizing.grow
    end

    # Whether there is anything to place.
    def image? : Bool
      !@image.nil?
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      wanted = Unicode.string_width @alt, policy
      Layout::Intrinsic.new Math.min(wanted, 1), wanted
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @alt.empty? ? 0 : 1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if @alt.empty? || view.width <= 0 || view.height <= 0

      Readout.line view, 0, @alt, @align, "…"
    end

    # Asks for the picture to be drawn across the box this widget was given.
    #
    # Nothing is asked at all without a store, and a store built for a terminal
    # that draws no pictures sends no bytes, so a picture in a tree costs
    # nothing where there is no way to show it.
    def place_images(store : ImageStore, frame : Rect) : Nil
      picture = @image
      return if picture.nil? || frame.empty?

      store.place picture, frame, @z
    end
  end
end
