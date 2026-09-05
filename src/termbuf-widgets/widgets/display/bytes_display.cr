require "../../widget"

module TermBuf::Widgets
  # A byte count in the unit that suits its size.
  #
  #     BytesDisplay.new 1023          # 1023 B
  #     BytesDisplay.new 1024          # 1.0 KiB
  #     BytesDisplay.new 1_500_000, standard: :si   # 1.5 MB
  #
  # Under the base — 1024 for IEC, 1000 for SI — the count is drawn whole, in
  # bytes, with no decimals: `1023 B` rather than `1023.0 B`. Above it the
  # count is divided down and drawn to `#precision` decimals.
  #
  # Rounding is checked against the unit it landed in. 1048575 bytes is
  # 1023.999 KiB, which at one decimal reads `1024.0 KiB`; that is a megabyte
  # written the long way, so the unit is stepped up and it comes out `1.0 MiB`.
  #
  # The widget fits its own text and is one row tall.
  class BytesDisplay < Widget
    # Which set of units and which base.
    enum Standard
      # Powers of 1024, named `KiB` upward.
      IEC

      # Powers of 1000, named `KB` upward.
      SI

      # Bytes to the next unit.
      def base : Int32
        case self
        in .iec? then 1024
        in .si?  then 1000
        end
      end

      # The unit names, smallest first.
      def units : Array(String)
        case self
        in .iec? then %w[B KiB MiB GiB TiB PiB EiB]
        in .si?  then %w[B KB MB GB TB PB EB]
        end
      end
    end

    # The count.
    layout_property bytes : Int64 = 0_i64

    # Which units it is drawn in.
    layout_property standard : Standard = Standard::IEC

    # Decimals shown once the count is past the base. Bytes are always whole.
    layout_property precision : Int32 = 1

    # Whether a space sits between the number and its unit.
    layout_property? space : Bool = true

    # Which side of the box the count sits on.
    layout_property align : Unicode::Align = Unicode::Align::Left

    # What marks a count cut short, or `nil` to cut it unmarked.
    layout_property ellipsis : String? = "…"

    def initialize(bytes : Int = 0,
                   standard : Standard = Standard::IEC,
                   precision : Int32 = 1,
                   space : Bool = true,
                   align : Unicode::Align = Unicode::Align::Left,
                   ellipsis : String? = "…",
                   style : Style? = nil)
      raise ArgumentError.new "precision #{precision} is negative" if precision < 0

      @bytes = bytes.to_i64
      @standard = standard
      @precision = precision
      @space = space
      @align = align
      @ellipsis = ellipsis
      @style = style
    end

    # Sets the count, from any integer.
    def bytes=(bytes : Int) : Int64
      self.bytes = bytes.to_i64
    end

    # The count as it is drawn: the number, then its unit.
    def text : String
      amount, unit = scaled
      sign = @bytes < 0 ? "-" : ""
      gap = @space ? " " : ""

      return "#{sign}#{amount.to_i64}#{gap}#{unit}" if unit == "B"

      "#{sign}#{"%.#{@precision}f" % amount}#{gap}#{unit}"
    end

    # How large the count is in the unit it landed in, and what that unit is
    # called.
    #
    # The step up happens twice: once while dividing, and once more when the
    # rounding the drawing does would have carried the number back to the
    # base.
    def scaled : {Float64, String}
      base = @standard.base
      units = @standard.units
      amount = @bytes.abs.to_f
      index = 0

      while amount >= base && index < units.size - 1
        amount /= base
        index += 1
      end

      if index < units.size - 1 && index > 0 && rounds_up?(amount, base)
        amount /= base
        index += 1
      end

      {amount, units[index]}
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

    # Whether *amount* drawn to `#precision` decimals reads as a whole *base*.
    private def rounds_up?(amount : Float64, base : Int32) : Bool
      ("%.#{@precision}f" % amount).to_f >= base
    end

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
