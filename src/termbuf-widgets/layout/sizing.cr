module TermBuf::Widgets::Layout
  # Which of the two axes a pass, an anchor or an overflow rule is working on.
  enum Axis
    # Columns.
    X

    # Rows.
    Y

    # The other one.
    def other : Axis
      case self
      in .x? then Y
      in .y? then X
      end
    end
  end

  # Which way a widget stacks its children.
  enum Direction
    # Left to right.
    Row

    # Top to bottom.
    Column
  end

  # Where a widget sits in space its parent did not give away.
  enum Align
    Start
    Center
    End
  end

  # Where a run of text is allowed to break.
  enum Wrap
    # Between words, and inside one only when a single word is wider than the
    # line.
    Words

    # Between any two grapheme clusters.
    Anywhere

    # Nowhere. The line is cut at the edge instead.
    None
  end

  # What a widget needs on one axis and what it would rather have.
  #
  # `min` is the point below which the content stops meaning anything: a
  # label's shortest word, a table's narrowest column. `preferred` is the
  # size at which nothing is compressed.
  record Intrinsic, min : Int32 = 0, preferred : Int32 = 0 do
    # An intrinsic that wants and needs the same *cells*.
    def self.exact(cells : Int32) : Intrinsic
      new cells, cells
    end
  end

  # How a widget asks to be sized on one axis.
  #
  # The four modes are resolved in the order they can be: `Fixed` is known
  # before anything else, `Fit` comes from the content, `Percent` is a share
  # of the parent's content box, and `Grow` divides whatever is left. `min`
  # and `max` bound the result in every mode.
  struct Sizing
    enum Mode
      # As large as the content needs, and no larger.
      Fit

      # A share of the space the parent has not otherwise spoken for.
      Grow

      # Exactly the number of cells given.
      Fixed

      # A share of the parent's content box, in hundredths.
      Percent
    end

    # Which of the four rules applies.
    getter mode : Mode

    # The smallest this widget may be laid out at.
    getter min : Int32

    # The largest this widget may be laid out at.
    getter max : Int32

    # A grow share, or a percent numerator out of 100. Zero in the other two
    # modes.
    getter weight : Int32

    def initialize(@mode : Mode, @min : Int32 = 0, @max : Int32 = Int32::MAX, @weight : Int32 = 0)
      raise ArgumentError.new "sizing minimum #{@min} is negative" if @min < 0
      raise ArgumentError.new "sizing maximum #{@max} is below its minimum #{@min}" if @max < @min
      raise ArgumentError.new "sizing weight #{@weight} is negative" if @weight < 0
    end

    # As large as the content needs, bounded by *min* and *max*.
    def self.fit(min : Int32 = 0, max : Int32 = Int32::MAX) : Sizing
      new Mode::Fit, min, max
    end

    # A share of the leftover space, *weight* against the other growers.
    def self.grow(weight : Int32 = 1, min : Int32 = 0, max : Int32 = Int32::MAX) : Sizing
      new Mode::Grow, min, max, weight
    end

    # Exactly *cells* cells.
    def self.fixed(cells : Int32) : Sizing
      raise ArgumentError.new "fixed size #{cells} is negative" if cells < 0

      new Mode::Fixed, cells, cells
    end

    # *percent* hundredths of the parent's content box on this axis.
    def self.percent(percent : Int32) : Sizing
      raise ArgumentError.new "percent #{percent} is outside 0..100" unless 0 <= percent <= 100

      new Mode::Percent, 0, Int32::MAX, percent
    end

    {% for name in Mode.constants %}
      # Whether this is a `Mode::{{ name }}` sizing.
      def {{ name.downcase }}? : Bool
        @mode.{{ name.downcase }}?
      end
    {% end %}

    # This sizing with a different floor.
    def with_min(min : Int32) : Sizing
      Sizing.new @mode, min, Math.max(@max, min), @weight
    end

    # This sizing with a different ceiling.
    def with_max(max : Int32) : Sizing
      Sizing.new @mode, Math.min(@min, max), max, @weight
    end

    # *cells* held inside this sizing's bounds.
    def clamp(cells : Int32) : Int32
      cells.clamp @min, @max
    end

    def to_s(io : IO) : Nil
      return io << "Sizing(fixed " << @min << ')' if fixed?

      io << "Sizing(" << @mode
      io << ' ' << @weight unless fit?
      io << " min=" << @min if @min > 0
      io << " max=" << @max if @max < Int32::MAX
      io << ')'
    end
  end
end
