require "../widget"
require "../layout/text_measure"

module TermBuf::Widgets
  # A run of text laid out and drawn in whatever space it is given.
  #
  # The measurement is done once per string and kept, so a resize costs a
  # walk over words rather than a walk over characters. It is done under the
  # tree's `TermBuf::Unicode::WidthPolicy`, which is what the terminal was
  # probed for, so the width the layout reserves is the width the terminal
  # draws.
  #
  #     label = Label.new "the quick brown fox"
  #     label.wrap = Layout::Wrap::Words
  #     label.width = Layout::Sizing.grow
  #
  # A label is a leaf: `#intrinsic_width` says how narrow it can go without
  # splitting a word, and `#height_for_width` says how many rows it turns out
  # to be once the width is settled.
  class Label < Widget
    # What is drawn.
    layout_property text : String = ""

    # Where the lines are allowed to break.
    layout_property wrap : Layout::Wrap = Layout::Wrap::Words

    # Which side of the line the text sits on when there is room to spare.
    property align : Unicode::Align = Unicode::Align::Left

    # What marks a line cut short at the right edge, or `nil` to cut it
    # without a mark. Only reached when a line is wider than the space it is
    # drawn in, which is what `Layout::Wrap::None` leaves it as.
    property ellipsis : String? = nil

    @measured : Layout::TextMeasure::Measured?
    @wrapped : Array(Layout::TextMeasure::Line)?
    @wrapped_width : Int32 = -1

    def initialize(@text : String = "", wrap : Layout::Wrap = Layout::Wrap::Words,
                   align : Unicode::Align = Unicode::Align::Left,
                   ellipsis : String? = nil)
      @wrap = wrap
      @align = align
      @ellipsis = ellipsis
    end

    def text=(text : String) : String
      forget unless @text == text
      previous_def
    end

    def wrap=(wrap : Layout::Wrap) : Layout::Wrap
      @wrapped = nil unless @wrap == wrap
      previous_def
    end

    # The measurement of the current text under *policy*, taken once and kept
    # until the text or the policy changes.
    def measured(policy : Unicode::WidthPolicy) : Layout::TextMeasure::Measured
      kept = @measured
      return kept if kept && kept.policy == policy

      forget
      fresh = Layout::TextMeasure.measure @text, policy
      @measured = fresh
      fresh
    end

    # The lines the text breaks into at *width*, taken once and kept until
    # the width, the text, the wrap mode or the policy changes.
    def wrapped(width : Int32, policy : Unicode::WidthPolicy) : Array(Layout::TextMeasure::Line)
      data = measured policy
      kept = @wrapped
      return kept if kept && @wrapped_width == width

      fresh = Layout::TextMeasure.wrap data, width, @wrap
      @wrapped = fresh
      @wrapped_width = width
      fresh
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      data = measured policy
      Layout::Intrinsic.new data.minimum(@wrap), data.width
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      wrapped(width, policy).size
    end

    # Writes the wrapped lines through *view*, which is already cut to this
    # widget's rectangle.
    def draw(view : View) : Nil
      return if @text.empty? || view.width <= 0

      paint = @style || Style::DEFAULT
      marker = @ellipsis

      wrapped(view.width, view.policy).each_with_index do |line, row|
        break if row >= view.height
        next if line.empty?

        text = line.text @text
        text = Unicode.ellipsize text, view.width, marker, view.policy if marker && line.width > view.width
        view.write column_for(line, view), row, text, paint
      end
    end

    # Where a line starts, given the room left over on it.
    private def column_for(line : Layout::TextMeasure::Line, view : View) : Int32
      room = view.width - line.width
      return 0 if room <= 0

      case @align
      in .left?   then 0
      in .right?  then room
      in .center? then room // 2
      end
    end

    # Throws away everything derived from the text.
    private def forget : Nil
      @measured = nil
      @wrapped = nil
      @wrapped_width = -1
    end
  end
end
