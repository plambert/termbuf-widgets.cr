require "../../message"
require "../../router"
require "../../widget"
require "../display/progress_bar"
require "../field"
require "./interactive"

module TermBuf::Widgets
  # A field holding one integer, stepped with the arrow keys.
  #
  #     wheel = NumberField.new value: 3, range: 1..10
  #     wheel.bar = true
  #     root.add wheel
  #
  # `Left` and `Down` step down, `Right` and `Up` step up, and `Home` and `End`
  # go to the ends of `#range`. Digits are typed and edited as in any `Field`.
  # `Enter` accepts the text and holds it to the range. Text that is not an
  # integer is put back to the last value.
  #
  # Every step that moves the value and every accept emits `Changed` with the
  # value. Setting `#value` from the application draws it and sends nothing.
  #
  # With `#bar` on, a filled bar beside the number shows where the value sits
  # in the range. The bar only draws. It takes no keys of its own.
  class NumberField < Field
    # The value moved, by a step or by an accepted line.
    struct Changed < Message
      # Which field it was.
      getter field : NumberField

      # What it now holds.
      getter value : Int32

      def initialize(@field : NumberField, @value : Int32)
      end
    end

    # The marks the bar is drawn with where they measure one cell each, and
    # the ASCII marks used everywhere else.
    BAR_MARKS = {'█', '░'}

    # :ditto:
    BAR_ASCII = {'#', '-'}

    # Cells between the number and the bar.
    BAR_GAP = 1

    # The value the field last accepted or was set to.
    getter value : Int32

    # The lowest and highest values, both included.
    getter range : Range(Int32, Int32)

    # How far one arrow press moves the value.
    property step : Int32

    # Whether the bar is drawn beside the number.
    layout_property? bar : Bool = false

    # Cells the bar takes when it is drawn.
    layout_property bar_width : Int32 = 10

    # Whether `Up` and `Down` step the value as well as `Left` and `Right`.
    # A `Form` turns this off, since there they move between rows.
    getter? up_down : Bool

    # Whether the field refuses the keyboard. It is still drawn, dimmed.
    layout_property? disabled : Bool = false

    # What the field is drawn in while it is disabled.
    property disabled_style : Style = Style::DEFAULT.faint

    # What draws the bar. Set its styles to color it.
    getter meter : ProgressBar

    def initialize(value : Int32 = 0,
                   range : Range(Int32, Int32) = 0..100,
                   @step : Int32 = 1,
                   bar : Bool = false,
                   bar_width : Int32 = 10,
                   up_down : Bool = true,
                   border : Border? = nil,
                   style : Style? = Style::DEFAULT)
      super border: border, style: style
      @range = NumberField.inclusive range
      @value = value.clamp @range.begin, @range.end
      @bar = bar
      @bar_width = bar_width
      @up_down = up_down
      @width = Layout::Sizing.fit
      @meter = ProgressBar.new filled_style: Style::DEFAULT, empty_style: Style::DEFAULT
      show_value
      self.keymap = stepping
    end

    # *range* with its end included, so that `0...10` and `0..9` are the same.
    def self.inclusive(range : Range(Int32, Int32)) : Range(Int32, Int32)
      low = range.begin
      high = range.excludes_end? ? range.end - 1 : range.end
      raise ArgumentError.new "range #{range} holds no values" if high < low

      low..high
    end

    # Sets the value, held to the range, and draws it. Sends nothing.
    def value=(value : Int32) : Int32
      @value = value.clamp @range.begin, @range.end
      show_value
      @value
    end

    # Sets the range and holds the value to it. Sends nothing.
    def range=(range : Range(Int32, Int32)) : Range(Int32, Int32)
      @range = NumberField.inclusive range
      self.value = @value
      invalidate_layout
      @range
    end

    # Turns `Up` and `Down` stepping on or off.
    def up_down=(on : Bool) : Bool
      @up_down = on
      self.keymap = stepping
      on
    end

    # Focus lands here unless the field is disabled.
    def focusable? : Bool
      !@disabled
    end

    # Moves the value *count* steps, held to the range, and says so when it
    # moved. Steps from the typed text when that is an integer.
    def step_by(count : Int32) : Nil
      return if @disabled

      base = typed || @value
      wanted = (base.to_i64 + count.to_i64 * @step).clamp(@range.begin.to_i64, @range.end.to_i64).to_i32
      moved = wanted != @value
      @value = wanted
      show_value
      emit Changed.new(self, @value) if moved
    end

    # Puts the value at *target*, held to the range, and says so when it moved.
    def go_to(target : Int32) : Nil
      return if @disabled

      wanted = target.clamp @range.begin, @range.end
      moved = wanted != @value
      @value = wanted
      show_value
      emit Changed.new(self, @value) if moved
    end

    # Takes *line* as the value, held to the range, or puts the last value
    # back when it is not an integer. Says so either way.
    def commit(line : String = text) : Nil
      found = line.strip.to_i32?
      @value = found.clamp(@range.begin, @range.end) if found
      show_value
      emit Changed.new(self, @value)
    end

    # Takes the typed text when it differs from what is shown, and does
    # nothing otherwise. What a form calls when the keyboard leaves the row.
    def settle : Nil
      commit unless text == @value.to_s
    end

    # The typed text as an integer, or `nil` when it is not one.
    def typed : Int32?
      text.strip.to_i32?
    end

    # Does what *key* means to the editor, keeping the line in the field when
    # it is accepted.
    def press(key : Key) : Nil
      return if @disabled

      outcome = @editor.handle key
      invalidate_layout

      case outcome
      in .continue? then nil
      in .accepted?
        commit @editor.accepted
        emit Accepted.new(text)
      in .cancelled?
        show_value
        emit Cancelled.new
      in .ended? then emit EndOfInput.new
      end
    end

    # Takes nothing while disabled.
    def paste(text : String) : Nil
      super unless @disabled
    end

    private def show_value : Nil
      self.text = @value.to_s
    end

    private def stepping : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Left"), "a step down", ->(_context : Context) { step_by(-1); nil }
        map.bind Key.parse("Right"), "a step up", ->(_context : Context) { step_by 1; nil }
        if @up_down
          map.bind Key.parse("Down"), "a step down", ->(_context : Context) { step_by(-1); nil }
          map.bind Key.parse("Up"), "a step up", ->(_context : Context) { step_by 1; nil }
        end
        map.bind Key.parse("Home"), "the lowest value",
          ->(_context : Context) { go_to @range.begin; nil }
        map.bind Key.parse("End"), "the highest value",
          ->(_context : Context) { go_to @range.end; nil }
      end
    end

    # ------------------------------------------------------------- layout

    # Cells the number takes, which is the longest value in the range and one
    # more for the cursor after it.
    def number_width : Int32
      Math.max(@range.begin.to_s.size, @range.end.to_s.size) + 1
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy
      wanted = prompt_width + number_width
      wanted += BAR_GAP + @bar_width if @bar

      Layout::Intrinsic.new prompt_width + number_width, wanted
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy
      1
    end

    # Cells left for the text, which stops where the bar starts.
    def text_width : Int32
      Math.max Math.min(number_width, content.width - prompt_width), 0
    end

    # Holds the text still while it fits, rather than keeping a spare cell at
    # each end the way a long line does.
    def reflow : Nil
      if buffer.width < text_width
        @offset = 0
      else
        super
      end
    end

    # ------------------------------------------------------------ drawing

    def style : Style?
      base = @style || Style::DEFAULT
      @disabled ? base.merge(@disabled_style) : base
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      room = Math.min prompt_width + number_width, view.width
      super view.view(Rect.new(0, 0, room, view.height))
      draw_bar view, room + BAR_GAP if @bar
    end

    # Where the value sits in the range, from 0.0 at the bottom to 1.0 at the
    # top.
    def fraction : Float64
      span = @range.end.to_i64 - @range.begin.to_i64
      return 1.0 if span <= 0

      (@value.to_i64 - @range.begin.to_i64) / span.to_f
    end

    private def draw_bar(view : View, left : Int32) : Nil
      cells = Math.min @bar_width, view.width - left
      return if cells <= 0

      filled, empty = Glyphs.single_cell?(BAR_MARKS.map(&.to_s), view.policy) ? BAR_MARKS : BAR_ASCII
      @meter.filled_char = filled
      @meter.empty_char = empty
      @meter.value = fraction
      @meter.draw view.view(Rect.new(left, 0, cells, 1))
    end
  end
end
