require "../../message"
require "../../widget"
require "./mouse"

module TermBuf::Widgets
  # A value out of a maximum, drawn as a row of stars.
  #
  #     stars = Rating.new 3.5
  #     stars.editable = true
  #
  # Read-only by default: it is a way of showing a score, and only a rating
  # told it is `#editable?` takes focus, binds keys, or answers a click.
  #
  # ### Glyphs
  #
  # `#glyphs` is a set of three characters — full, half, empty. Left `nil`,
  # which is the default, the set is chosen from the tree's
  # `TermBuf::Unicode::WidthPolicy` at every layout: `Glyphs::UNICODE` when
  # every one of its characters is a single cell under that policy, and
  # `Glyphs::ASCII` when one of them is not.
  #
  # That check is the whole of the fallback, and it earns its keep. `★` and `☆`
  # are East Asian Ambiguous, so a terminal configured for CJK text draws them
  # two cells wide while `⯪` stays at one — a row that would come out ragged.
  # The policy says so, and the ASCII set is used instead. Setting `#glyphs`
  # names a set outright and skips the question.
  #
  # ### Editing
  #
  # An editable rating binds `Left` and `Right` to a step of `#step`, `Home`
  # and `End` to the ends, and the digit keys to that many stars. A left click
  # on a star sets the value to it. Every change that lands emits `Changed`.
  class Rating < Widget
    # The value changed, because somebody changed it.
    struct Changed < Message
      # What it is now.
      getter value : Float64

      def initialize(@value : Float64)
      end
    end

    # The three characters a rating is drawn with.
    record Glyphs, full : Char, half : Char, empty : Char do
      # Stars, which is what a rating looks like when the terminal can draw
      # one.
      UNICODE = new '★', '⯪', '☆'

      # The fallback, for a policy that would draw the stars ragged.
      ASCII = new '*', '+', '-'

      # Whether every character here is exactly one cell under *policy*.
      def single_width?(policy : Unicode::WidthPolicy) : Bool
        each.all? { |char| Unicode.string_width(char.to_s, policy) == 1 }
      end

      # The widest of the three under *policy*, which is the stride a row of
      # them is laid out on.
      def width(policy : Unicode::WidthPolicy) : Int32
        each.max_of { |char| Unicode.string_width char.to_s, policy }
      end

      # The set to use under *policy* when nothing named one.
      def self.for(policy : Unicode::WidthPolicy) : Glyphs
        UNICODE.single_width?(policy) ? UNICODE : ASCII
      end

      # The three, full first.
      def each : Iterator(Char)
        {@full, @half, @empty}.each
      end
    end

    # Left and Right move by this much.
    STEP = 1.0

    # How many stars there are.
    layout_property max : Int32 = 5

    # Cells between one star and the next.
    layout_property spacing : Int32 = 0

    # The characters to draw with, or `nil` to choose from the width policy.
    layout_property glyphs : Glyphs? = nil

    # What a full star is drawn in.
    property filled_style : Style = Style::DEFAULT

    # What an empty star is drawn in.
    property empty_style : Style = Style::DEFAULT.faint

    # How far `Left` and `Right` move the value.
    property step : Float64 = STEP

    # How clusters are measured, taken from the tree at every layout.
    getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

    @value : Float64 = 0.0
    @editable : Bool = false

    def initialize(value : Number = 0.0,
                   max : Int32 = 5,
                   editable : Bool = false,
                   glyphs : Glyphs? = nil,
                   spacing : Int32 = 0,
                   step : Float64 = STEP,
                   filled_style : Style = Style::DEFAULT,
                   empty_style : Style = Style::DEFAULT.faint,
                   style : Style? = nil)
      raise ArgumentError.new "max #{max} is not positive" if max < 1

      @max = max
      @glyphs = glyphs
      @spacing = spacing
      @step = step
      @filled_style = filled_style
      @empty_style = empty_style
      @style = style
      @value = value.to_f.clamp 0.0, max.to_f
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fit
      self.editable = editable
    end

    # How many stars are earned, from zero to `#max`.
    def value : Float64
      @value
    end

    # Sets the value, holding it between zero and `#max`.
    #
    # No invalidation: how wide the row is comes from `#max`, not from the
    # value, so nothing about the layout turns on this.
    def value=(value : Float64) : Float64
      @value = value.clamp 0.0, @max.to_f
    end

    # :ditto:
    def value=(value : Number) : Float64
      self.value = value.to_f
    end

    # Sets how many stars there are, bringing the value back inside them.
    def max=(max : Int32) : Int32
      raise ArgumentError.new "max #{max} is not positive" if max < 1

      previous_def
      @value = @value.clamp 0.0, max.to_f
      max
    end

    # Whether the value can be changed from the keyboard or the mouse.
    def editable? : Bool
      @editable
    end

    # Sets whether the value can be changed, binding or unbinding the keys
    # that do it.
    def editable=(editable : Bool) : Bool
      return editable if @editable == editable

      @editable = editable
      self.keymap = editable ? bindings : nil
      editable
    end

    # Focus lands here only on a rating somebody can change.
    def focusable? : Bool
      @editable
    end

    # The characters this rating draws with under *policy*.
    def glyphs_for(policy : Unicode::WidthPolicy = @policy) : Glyphs
      @glyphs || Glyphs.for(policy)
    end

    # Cells from the start of one star to the start of the next.
    def stride(policy : Unicode::WidthPolicy = @policy) : Int32
      glyphs_for(policy).width(policy) + @spacing
    end

    # Which of the three characters star *index* gets, counting from zero.
    def glyph_at(index : Int32, policy : Unicode::WidthPolicy = @policy) : Char
      set = glyphs_for policy
      earned = @value - index

      return set.full if earned >= 1.0
      return set.half if earned >= 0.5

      set.empty
    end

    # ------------------------------------------------------------- events

    # Sets the value and says so, when that changed anything.
    def change_to(value : Float64) : Nil
      was = @value
      self.value = value
      emit Changed.new(@value) unless @value == was
    end

    # Moves the value by *amount*, and says so.
    def step_by(amount : Float64) : Nil
      change_to @value + amount
    end

    # A left click on a star sets the value to it. Everything else is
    # somebody else's.
    def handle(event : Event, context : Context) : Nil
      return unless @editable
      return unless event.is_a? Events::Mouse
      return unless event.action.press? && event.button.left?

      index = star_at event.x, event.y
      return unless index

      change_to (index + 1).to_f
      context.consume
    end

    # Which star (*x*, *y*) falls on, in buffer coordinates, or `nil` when it
    # falls between stars or outside the row altogether.
    def star_at(x : Int32, y : Int32) : Int32?
      box = content
      return unless box.contains? x, y

      column = x - box.x
      index = column // stride
      return unless 0 <= index < @max

      # A click in the gap after a star belongs to nothing: the gap is not
      # part of the star it follows.
      return if column - index * stride >= glyphs_for.width(@policy)

      index
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy
      cells = @max * glyphs_for(policy).width(policy) + (@max - 1) * @spacing

      Layout::Intrinsic.new Math.min(cells, 1), cells
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy
      1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      step = stride view.policy

      @max.times do |index|
        column = index * step
        break if column >= view.width

        char = glyph_at index, view.policy
        view.write_char column, 0, char, style_for(char, view.policy)
      end
    end

    private def style_for(char : Char, policy : Unicode::WidthPolicy) : Style
      char == glyphs_for(policy).empty ? @empty_style : @filled_style
    end

    # The keys an editable rating answers.
    private def bindings : Bindings
      Bindings.build do |map|
        map.bind Key.named(Key::Name::Left), "a step down",
          ->(_context : Context) { step_by(-@step); nil }
        map.bind Key.named(Key::Name::Right), "a step up",
          ->(_context : Context) { step_by(@step); nil }
        map.bind Key.named(Key::Name::Home), "no stars at all",
          ->(_context : Context) { change_to 0.0; nil }
        map.bind Key.named(Key::Name::End), "every star",
          ->(_context : Context) { change_to @max.to_f; nil }

        (0..9).each do |digit|
          map.bind Key.character('0' + digit), "#{digit} stars",
            ->(_context : Context) { change_to digit.to_f; nil }
        end
      end
    end
  end
end
