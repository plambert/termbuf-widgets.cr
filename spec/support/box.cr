# Stand-ins for real widgets, so a layout can be checked without any text
# measurement or drawing in the way.
module Fixtures
  # A widget that draws nothing and reports whatever intrinsic size it is told
  # to.
  class Box < TermBuf::Widgets::Widget
    alias Intrinsic = TermBuf::Widgets::Layout::Intrinsic

    # What `#intrinsic_width` answers.
    property intrinsic : Intrinsic

    # What `#height_for_width` answers.
    property lines : Int32

    def initialize(@intrinsic : Intrinsic = Intrinsic.new(0, 0), @lines : Int32 = 0)
    end

    # A box that wants *width* columns and *height* rows, and will go no
    # narrower than it wants.
    def self.sized(width : Int32, height : Int32 = 0) : Box
      new Intrinsic.exact(width), height
    end

    # A box that wants *preferred* columns but survives in *min* of them.
    def self.flexible(min : Int32, preferred : Int32, height : Int32 = 0) : Box
      new Intrinsic.new(min, preferred), height
    end

    def intrinsic_width(policy : TermBuf::Unicode::WidthPolicy) : Intrinsic
      @intrinsic
    end

    def height_for_width(width : Int32, policy : TermBuf::Unicode::WidthPolicy) : Int32
      @lines
    end

    # Changes the gap behind the setter's back, which is what a widget written
    # without `layout_property` would do by accident.
    def poke_gap(gap : Int32) : Nil
      @gap = gap
    end
  end
end
