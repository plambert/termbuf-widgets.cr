require "../../widget"

module TermBuf::Widgets
  # A number, written the way a person reads one.
  #
  #     FormattedNumber.new 1_234_567.891, decimals: 2, unit: "ms"
  #     # draws: 1,234,567.89 ms
  #
  # Grouping separator, decimal point, how many decimals, whether a positive
  # number carries its sign, and a unit after it. All of them are geometry —
  # each one changes how wide the number is — so all of them go through
  # `Widget#layout_property` and a change to any marks the tree.
  #
  # The widget fits its own text and is one row tall. In less room than the
  # number needs it is cut and marked with `#ellipsis`: a number silently
  # missing its last digits is worse than one that says it was cut.
  class FormattedNumber < Widget
    # The number itself.
    layout_property value : Float64 = 0.0

    # Digits after the decimal point. Zero for none, and no point either.
    layout_property decimals : Int32 = 0

    # What goes between groups of digits, or `""` for no grouping at all.
    layout_property grouping : String = ","

    # Digits to a group.
    layout_property group_size : Int32 = 3

    # What separates the whole part from the fraction.
    layout_property point : String = "."

    # Whether a number above zero carries a `+`. A negative one always carries
    # its `-`.
    layout_property? sign : Bool = false

    # What follows the number, or `nil` for none.
    layout_property unit : String? = nil

    # Whether a space sits between the number and its unit.
    layout_property? unit_space : Bool = true

    # What marks a number cut short, or `nil` to cut it unmarked.
    layout_property ellipsis : String? = "…"

    # Which side of the box the number sits on.
    layout_property align : Unicode::Align = Unicode::Align::Left

    def initialize(value : Number = 0,
                   decimals : Int32 = 0,
                   grouping : String = ",",
                   group_size : Int32 = 3,
                   point : String = ".",
                   sign : Bool = false,
                   unit : String? = nil,
                   unit_space : Bool = true,
                   align : Unicode::Align = Unicode::Align::Left,
                   ellipsis : String? = "…",
                   style : Style? = nil)
      raise ArgumentError.new "decimals #{decimals} is negative" if decimals < 0
      raise ArgumentError.new "group size #{group_size} is not positive" if group_size < 1

      @value = value.to_f
      @decimals = decimals
      @grouping = grouping
      @group_size = group_size
      @point = point
      @sign = sign
      @unit = unit
      @unit_space = unit_space
      @align = align
      @ellipsis = ellipsis
      @style = style
    end

    # Sets the number, from anything that is one.
    def value=(value : Number) : Float64
      self.value = value.to_f
    end

    # The number as it is drawn: sign, grouped digits, decimals, unit.
    def text : String
      String.build do |line|
        line << sign_of
        line << digits
        write_unit line
      end
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      cells = Unicode.string_width text, policy
      Layout::Intrinsic.new Math.min(cells, 1), cells
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      shown = Unicode.ellipsize text, view.width, @ellipsis || "", view.policy
      return if shown.empty?

      view.write column_for(shown, view), 0, shown, @style || Style::DEFAULT
    end

    # What goes in front: a `-` below zero, a `+` above it when `#sign?`.
    private def sign_of : String
      return "-" if @value < 0
      return "+" if @sign && @value > 0

      ""
    end

    # The digits, grouped, with the decimals after them.
    private def digits : String
      rounded = "%.#{@decimals}f" % @value.abs
      whole, _, fraction = rounded.partition '.'
      grouped = group whole

      fraction.empty? ? grouped : "#{grouped}#{@point}#{fraction}"
    end

    # *whole* with `#grouping` every `#group_size` digits, counted from the
    # right so the leftmost group is the short one.
    private def group(whole : String) : String
      return whole if @grouping.empty? || whole.size <= @group_size

      pieces = [] of String
      stop = whole.size

      while stop > @group_size
        pieces.unshift whole[(stop - @group_size)...stop]
        stop -= @group_size
      end

      pieces.unshift whole[0...stop]
      pieces.join @grouping
    end

    private def write_unit(line : String::Builder) : Nil
      unit = @unit
      return unless unit

      line << ' ' if @unit_space
      line << unit
    end

    # Where the number starts, given the room left over.
    private def column_for(text : String, view : View) : Int32
      room = view.width - Unicode.string_width(text, view.policy)
      return 0 if room <= 0

      case @align
      in .left?   then 0
      in .right?  then room
      in .center? then room // 2
      end
    end
  end
end
