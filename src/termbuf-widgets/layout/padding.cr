module TermBuf::Widgets::Layout
  # Cells held back on each side of a widget's own rectangle.
  #
  # Padding is inside the widget: a widget ten cells wide with a padding of
  # one has eight cells of content. A `Border` adds another cell per side; see
  # `Widget#inset`, which is padding and border together.
  record Padding, top : Int32 = 0, right : Int32 = 0, bottom : Int32 = 0, left : Int32 = 0 do
    # The same number of cells on every side.
    def self.all(cells : Int32) : Padding
      new cells, cells, cells, cells
    end

    # *left* and *right*, then *top* and *bottom*.
    def self.symmetric(horizontal : Int32 = 0, vertical : Int32 = 0) : Padding
      new vertical, horizontal, vertical, horizontal
    end

    # Cells taken out of the width.
    def horizontal : Int32
      @left + @right
    end

    # Cells taken out of the height.
    def vertical : Int32
      @top + @bottom
    end

    # Whether every side is zero.
    def zero? : Bool
      @top.zero? && @right.zero? && @bottom.zero? && @left.zero?
    end

    # Side by side.
    def +(other : Padding) : Padding
      Padding.new @top + other.top, @right + other.right,
        @bottom + other.bottom, @left + other.left
    end
  end
end
