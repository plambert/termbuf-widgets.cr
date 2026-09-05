require "../../widget"

module TermBuf::Widgets
  # One line of text a widget works out for itself rather than being handed.
  #
  # `Label` is the widget for text somebody set. This is the base for the ones
  # that compute it: a `Clock` from the time, a `RelativeTime` from how long
  # ago something was, an `Icon` from which glyph the terminal can draw. All
  # any of them has to supply is `#text`.
  #
  # The line is measured under the tree's `TermBuf::Unicode::WidthPolicy`, sits
  # where `#align` asks for in whatever room is left over, and is cut with
  # `#ellipsis` when there is not enough.
  abstract class Readout < Widget
    # Which side of the box the line sits on when there is room to spare.
    layout_property align : Unicode::Align = Unicode::Align::Left

    # What marks a line cut short, or `nil` to cut it unmarked.
    layout_property ellipsis : String? = "…"

    # What the line says.
    abstract def text : String

    # Writes *text* on row *index* of *view*, cut to fit and put where *align*
    # asks for. Draws nothing at all for an empty line.
    def self.line(view : View, index : Int32, text : String,
                  align : Unicode::Align, ellipsis : String?,
                  style : Style? = nil) : Nil
      return if text.empty? || index >= view.height

      shown = Unicode.ellipsize text, view.width, ellipsis || "", view.policy
      return if shown.empty?

      column = Readout.column_for shown, view, align
      return view.write column, index, shown unless style

      view.write column, index, shown, style
    end

    # Where a line starts in *view*, given the room left over on it.
    def self.column_for(text : String, view : View, align : Unicode::Align) : Int32
      room = view.width - Unicode.string_width(text, view.policy)
      return 0 if room <= 0

      case align
      in .left?   then 0
      in .right?  then room
      in .center? then room // 2
      end
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      wanted = Unicode.string_width text, policy
      Layout::Intrinsic.new Math.min(wanted, 1), wanted
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      1
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      Readout.line view, 0, text, @align, @ellipsis
    end
  end
end
