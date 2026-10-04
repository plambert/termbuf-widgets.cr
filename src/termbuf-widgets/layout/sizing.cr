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
  # of what those two left of the parent's content box, and `Grow` divides
  # whatever is still over. `min` and `max` bound the result in every mode.
  #
  # Two more bounds are percentages, set with `#with_min_percent` and
  # `#with_max_percent`. Each is a percentage of a `Basis`, and they bound
  # every mode on either axis the same way `min` and `max` do.
  #
  # ```
  # Sizing.fit(min: 6).with_max_percent(25)                 # of the parent
  # Sizing.fit(min: 6).with_max_percent(25, of: :component) # of the component root
  # Sizing.grow.with_min_percent(30).with_max_percent(60)
  # ```
  #
  # Cells and percentages intersect. The floor is the larger of `min` and the
  # minimum percentage, and the ceiling the smaller of `max` and the maximum
  # percentage. When the floor comes out above the ceiling, the floor wins.
  #
  # `Fixed` stores its cells as both `min` and `max`, and those cells are the
  # size it asks for rather than a floor. The percentages bound that size
  # instead, so `Sizing.fixed(30).with_max_percent(25)` is thirty cells or a
  # quarter of its basis, whichever is smaller.
  struct Sizing
    enum Mode
      # As large as the content needs, and no larger.
      Fit

      # A share of the space the parent has not otherwise spoken for.
      Grow

      # Exactly the number of cells given.
      Fixed

      # A share, in hundredths, of what the parent's content box has left
      # once the gaps and the settled siblings have taken theirs.
      Percent
    end

    # What a percentage bound is a percentage of.
    #
    # `Parent` is the parent's whole content box. `Mode::Percent` is a share
    # of what the settled siblings left of that box, which is a smaller
    # number whenever the parent holds anything else. The two are easy to
    # confuse. A cap of 25% of the parent is a quarter of the parent's
    # content box, whatever its other children take.
    #
    # The engine lays a tree out in passes, and a basis can only bound a size
    # once it is known. `Screen` is known from the start, so it bounds a
    # widget everywhere a cell bound would. `Parent` and `Component` are known
    # only once the parent hands out its box, which happens after the
    # content has been measured from the bottom up. Until then they bound
    # nothing. The one exception is a `Component` basis with no component
    # root above it, which is the screen and bounds from the start. A `Fit`
    # widget capped below its content is reported at its
    # full width while its parent is measured, and cut down when the parent
    # hands out its box. A parent that is itself `Fit` has by then taken the
    # full width, and keeps it. See `Engine`.
    enum Basis
      # The content box of the widget's parent on that axis.
      #
      # A float has no room in its parent's box. For a float, this is
      # whatever it is anchored to, or the screen, which is what
      # `Mode::Percent` takes its share of there too.
      Parent

      # The content box of the nearest ancestor whose
      # `Widget#component_root?` is true, or the screen when no ancestor is
      # one. The lookup goes up through a float to the widgets it sits
      # under.
      Component

      # The whole area the tree is laid out into.
      Screen
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

    # The smallest this widget may be laid out at, in hundredths of
    # `#min_basis`, or `nil` for no such floor.
    getter min_percent : Int32?

    # The largest this widget may be laid out at, in hundredths of
    # `#max_basis`, or `nil` for no such ceiling.
    getter max_percent : Int32?

    # What `#min_percent` is a percentage of.
    getter min_basis : Basis

    # What `#max_percent` is a percentage of.
    getter max_basis : Basis

    def initialize(@mode : Mode, @min : Int32 = 0, @max : Int32 = Int32::MAX, @weight : Int32 = 0,
                   *, @min_percent : Int32? = nil, @max_percent : Int32? = nil,
                   @min_basis : Basis = Basis::Parent, @max_basis : Basis = Basis::Parent)
      raise ArgumentError.new "sizing minimum #{@min} is negative" if @min < 0
      raise ArgumentError.new "sizing maximum #{@max} is below its minimum #{@min}" if @max < @min
      raise ArgumentError.new "sizing weight #{@weight} is negative" if @weight < 0
      Sizing.check_percent "sizing minimum percent", @min_percent
      Sizing.check_percent "sizing maximum percent", @max_percent
    end

    # :nodoc:
    def self.check_percent(name : String, percent : Int32?) : Nil
      return unless percent
      return if 0 <= percent <= 100

      raise ArgumentError.new "#{name} #{percent} is outside 0..100"
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

    # *percent* hundredths of what is left of the parent's content box on this
    # axis: the box less the gaps between the children and less every sibling
    # already settled at a size, meaning the `Fixed` ones and the `Fit` ones.
    # Two panes at fifty each with a one-cell rule between them fill the box,
    # rather than claiming the rule's cell twice over and overflowing by one.
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
      copy min: min, max: Math.max(@max, min)
    end

    # This sizing with a different ceiling.
    def with_max(max : Int32) : Sizing
      copy min: Math.min(@min, max), max: max
    end

    # This sizing with a floor of *percent* hundredths of *basis*, in place of
    # any it had. The floor in cells stays, and the larger of the two holds.
    #
    # Raises `ArgumentError` when *percent* is outside 0..100.
    def with_min_percent(percent : Int32, of basis : Basis = Basis::Parent) : Sizing
      copy min_percent: percent, min_basis: basis
    end

    # This sizing with a ceiling of *percent* hundredths of *basis*, in place
    # of any it had. The ceiling in cells stays, and the smaller of the two
    # holds.
    #
    # `Sizing.fit(min: 6).with_max_percent(25, of: :component)` is as wide
    # as its content, never narrower than six cells, and never wider than a
    # quarter of the component root.
    #
    # Raises `ArgumentError` when *percent* is outside 0..100.
    def with_max_percent(percent : Int32, of basis : Basis = Basis::Parent) : Sizing
      copy max_percent: percent, max_basis: basis
    end

    # Whether either bound is a percentage.
    def percent_bounds? : Bool
      !@min_percent.nil? || !@max_percent.nil?
    end

    # *cells* held inside this sizing's bounds in cells. The percentages are
    # left out, because they need a basis, and `#bounds` takes them into
    # account.
    def clamp(cells : Int32) : Int32
      cells.clamp @min, @max
    end

    # The floor and the ceiling in cells, with each percentage taken of its
    # basis.
    #
    # The block answers how many cells a basis comes to, or `nil` when that
    # is not known yet. A percentage whose basis is unknown bounds nothing.
    # The block is not called for a bound that is not set, so a sizing with
    # no percentages costs nothing to ask.
    #
    # The ceiling is never below the floor. When the two cross, the ceiling
    # is raised to meet the floor.
    #
    # A `Mode::Fixed` sizing answers one number for both, which is its cells
    # held inside the percentages. Its cells are the size it asks for, so a
    # percentage cap can bring it down.
    def bounds(& : Basis -> Int32?) : {Int32, Int32}
      low = nil
      if (percent = @min_percent) && (whole = yield @min_basis)
        low = Sizing.share percent, whole
      end

      high = nil
      if (percent = @max_percent) && (whole = yield @max_basis)
        high = Sizing.share percent, whole
      end

      return {@min, @max} unless low || high
      return fixed_bounds(low, high) if fixed?

      floor = low ? Math.max(@min, low) : @min
      ceiling = high ? Math.min(@max, high) : @max
      {floor, Math.max(ceiling, floor)}
    end

    private def fixed_bounds(low : Int32?, high : Int32?) : {Int32, Int32}
      size = @min
      size = Math.min size, high if high
      size = Math.max size, low if low
      {size, size}
    end

    # The floor and the ceiling against the given bases, each in cells or
    # `nil` when it is not known.
    def bounds(parent : Int32? = nil, component : Int32? = nil, screen : Int32? = nil) : {Int32, Int32}
      bounds do |basis|
        case basis
        in .parent?    then parent
        in .component? then component
        in .screen?    then screen
        end
      end
    end

    # *percent* hundredths of *whole*, to the nearest cell.
    def self.share(percent : Int32, whole : Int32) : Int32
      ((percent.to_i64 * whole + 50) // 100).to_i32
    end

    def to_s(io : IO) : Nil
      if fixed?
        io << "Sizing(fixed " << @min
      else
        io << "Sizing(" << @mode
        io << ' ' << @weight unless fit?
        io << " min=" << @min if @min > 0
        io << " max=" << @max if @max < Int32::MAX
      end
      write_percent io, "min", @min_percent, @min_basis
      write_percent io, "max", @max_percent, @max_basis
      io << ')'
    end

    private def write_percent(io : IO, name : String, percent : Int32?, basis : Basis) : Nil
      return unless percent

      io << ' ' << name << '=' << percent << "% of " << basis.to_s.downcase
    end

    private def copy(min : Int32 = @min, max : Int32 = @max,
                     min_percent : Int32? = @min_percent, max_percent : Int32? = @max_percent,
                     min_basis : Basis = @min_basis, max_basis : Basis = @max_basis) : Sizing
      Sizing.new @mode, min, max, @weight, min_percent: min_percent, max_percent: max_percent,
        min_basis: min_basis, max_basis: max_basis
    end
  end
end
