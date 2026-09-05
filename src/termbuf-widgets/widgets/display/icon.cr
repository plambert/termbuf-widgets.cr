require "./picture"
require "./readout"

module TermBuf::Widgets
  # One glyph standing for something, with a plainer spelling for the
  # terminals that would draw the first one ragged.
  #
  #     Icon.new "★", fallback: "*"
  #     Icon.new "📁", fallback: "[]"
  #     Icon.new "●", fallback: "*", image: Image.png(path)
  #
  # ### The fallback
  #
  # An icon reserves `#cells` columns, and takes `#fallback` whenever `#glyph`
  # does not come out at exactly that many under the tree's width policy. Left
  # at zero, `#cells` is however wide the glyph is under
  # `TermBuf::Unicode::WidthPolicy::DEFAULT`, which is what makes the common
  # case work without being told anything: `★` is East Asian Ambiguous and
  # comes out two cells wide on a terminal configured for CJK text, so an icon
  # that reserved one gets the ASCII spelling instead, while `📁` is two cells
  # everywhere and is left alone.
  #
  # Naming a `#fallback` of `""` turns the check off and draws the glyph
  # whatever it measures.
  #
  # ### With a picture
  #
  # Given an `#image`, the icon asks for it over its own cells the way
  # `Picture` does, and the glyph is what is left on a terminal that draws no
  # pictures. Nothing branches on whether one does: the glyph goes down every
  # frame and the picture covers it where there is a picture to draw. See
  # `Picture` for why the question cannot be asked any earlier.
  class Icon < Readout
    # What is drawn.
    layout_property glyph : String = ""

    # What is drawn instead when `#glyph` does not measure `#cells`, or empty
    # to draw the glyph whatever it measures.
    layout_property fallback : String = ""

    # How many cells the icon reserves, or zero to take the glyph's own width
    # under the default policy. See the class docs.
    layout_property cells : Int32 = 0

    # A picture to put over the glyph, or `nil` for an icon that is only a
    # glyph.
    property image : Image? = nil

    # Where that picture sits against the text. See `TermBuf::Placement#z`.
    property z : Int32 = 0

    # How clusters are measured, taken from the tree at every layout.
    getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

    def initialize(@glyph : String = "",
                   fallback : String = "",
                   cells : Int32 = 0,
                   image : Image? = nil,
                   z : Int32 = 0,
                   align : Unicode::Align = Unicode::Align::Left,
                   style : Style? = nil)
      @fallback = fallback
      @cells = cells
      @image = image
      @z = z
      @align = align
      @style = style
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fixed 1
    end

    # How many cells the icon reserves.
    def reserved : Int32
      return @cells if @cells > 0

      Unicode.string_width @glyph, Unicode::WidthPolicy::DEFAULT
    end

    # Which of the two spellings is drawn under *policy*.
    def glyph_for(policy : Unicode::WidthPolicy = @policy) : String
      return @glyph if @fallback.empty?

      Unicode.string_width(@glyph, policy) == reserved ? @glyph : @fallback
    end

    # What the icon draws, under the policy the last layout used.
    def text : String
      glyph_for @policy
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy
      super
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy
      1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      Readout.line view, 0, glyph_for(view.policy), @align, @ellipsis
    end

    # Asks for the picture, when there is one, over the glyph.
    def place_images(store : ImageStore, frame : Rect) : Nil
      picture = @image
      return if picture.nil? || frame.empty?

      store.place picture, frame, @z
    end
  end
end
