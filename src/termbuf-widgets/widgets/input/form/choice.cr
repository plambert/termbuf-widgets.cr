require "../../../message"
require "../../../router"
require "../../../widget"
require "../interactive"

module TermBuf::Widgets
  class Form < Widget
    # One answer out of a few, every label drawn with a mark against the
    # chosen one.
    #
    #     choice = Form::Choice.new [{"gradient", "Gradient"}, {"bands", "Bands"}]
    #
    # The labels sit on one line when they fit the width the layout gives, and
    # one under another when they do not. The layout decides at every frame,
    # so a resize can move a choice between the two.
    #
    # `Left` and `Right` move the mark, stopping at either end. `Space` moves
    # it on and wraps. A click on a label takes it. Each emits `Changed` when
    # the mark moves.
    class Choice < Widget
      include Interactive

      # The mark moved.
      struct Changed < Message
        # Which choice it was.
        getter choice : Choice

        # The value now chosen.
        getter value : String

        def initialize(@choice : Choice, @value : String)
        end
      end

      # The marks drawn where `•` measures one cell, chosen and not.
      UNICODE = {"(•)", "( )"}

      # The marks drawn everywhere else.
      ASCII = {"(*)", "( )"}

      # Cells between one label and the next on a line.
      SPACING = 2

      # Each option as a value and the label drawn for it.
      getter options : Array({String, String})

      # Where the chosen option sits in `#options`.
      getter index : Int32 = 0

      # Whether the choice refuses the keyboard. It is still drawn, dimmed.
      layout_property? disabled : Bool = false

      # What the chosen label is drawn in while the choice has the keyboard.
      property focused_style : Style = Style::DEFAULT.reverse

      # What it is drawn in otherwise.
      property chosen_style : Style = Style::DEFAULT.bold

      # What everything is drawn in while the choice is disabled.
      property disabled_style : Style = Style::DEFAULT.faint

      # How clusters are measured, taken from the tree at every layout.
      getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

      def initialize(@options : Array({String, String}), value : String? = nil)
        raise ArgumentError.new "a choice needs at least one option" if @options.empty?

        @width = Layout::Sizing.grow
        self.value = value if value
        self.keymap = moving
      end

      # The value chosen.
      def value : String
        @options[@index][0]
      end

      # Chooses *value* and draws it. Sends nothing. Raises `ArgumentError`
      # for a value that is not one of the options.
      def value=(value : String) : String
        found = @options.index { |option| option[0] == value }
        raise ArgumentError.new "#{value.inspect} is not one of the options" unless found

        @index = found
        value
      end

      # Focus lands here unless the choice is disabled.
      def focusable? : Bool
        !@disabled
      end

      # Moves the mark *count* places, stopping at either end, and says so
      # when it moved.
      def move(count : Int32) : Nil
        choose (@index + count).clamp(0, @options.size - 1)
      end

      # Moves the mark on one, from the last back to the first.
      def cycle : Nil
        choose (@index + 1) % @options.size
      end

      # Chooses the option at *index* and says so when it moved.
      def choose(index : Int32) : Nil
        return if @disabled || index == @index || !(0 <= index < @options.size)

        @index = index
        emit Changed.new(self, value)
      end

      private def moving : Bindings
        Bindings.build do |map|
          map.bind Key.parse("Left"), "the option before", ->(_context : Context) { move(-1); nil }
          map.bind Key.parse("Right"), "the option after", ->(_context : Context) { move 1; nil }
          map.bind Key.parse("Space"), "the next option", ->(_context : Context) { cycle; nil }
        end
      end

      # Takes a click on a label, and swallows whatever is aimed at a disabled
      # choice.
      def handle(event : Event, context : Context) : Nil
        return unless event.is_a? Events::Mouse
        return context.consume if @disabled && frame.contains?(event.x, event.y)

        clicked event, context do
          take_focus context
          found = option_at event.x, event.y
          choose found if found
        end
      end

      # The option drawn at screen cell (*x*, *y*), or `nil` for none.
      def option_at(x : Int32, y : Int32) : Int32?
        box = content
        column = x - box.x
        row = y - box.y
        return unless 0 <= column < box.width && 0 <= row < box.height
        return (row < @options.size ? row : nil) unless inline?(box.width)

        left = 0
        @options.each_with_index do |option, position|
          cells = item_width option
          return position if left <= column < left + cells

          left += cells + SPACING
        end

        nil
      end

      # ----------------------------------------------------------- layout

      # The marks for *policy*.
      def marks_for(policy : Unicode::WidthPolicy) : {String, String}
        Glyphs.single_cell?(["•"], policy) ? UNICODE : ASCII
      end

      # Cells one option takes, which is its mark, a space and its label.
      def item_width(option : {String, String}) : Int32
        Unicode.string_width(marks_for(@policy)[0], @policy) + 1 +
          Unicode.string_width(option[1], @policy)
      end

      # Cells every option takes laid out on one line.
      def inline_width : Int32
        @options.sum { |option| item_width option } + SPACING * (@options.size - 1)
      end

      # Whether the options fit on one line *width* cells across.
      def inline?(width : Int32) : Bool
        inline_width <= width
      end

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        @policy = policy
        Layout::Intrinsic.new @options.max_of { |option| item_width option }, inline_width
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        @policy = policy
        inline?(width) ? 1 : @options.size
      end

      # ---------------------------------------------------------- drawing

      def style : Style?
        base = @style || Style::DEFAULT
        @disabled ? base.merge(@disabled_style) : base
      end

      def draw(view : View) : Nil
        return if view.width <= 0 || view.height <= 0

        chosen, other = marks_for view.policy
        lit = focused? ? @focused_style : @chosen_style
        across = inline? view.width
        left = 0

        @options.each_with_index do |option, position|
          picked = position == @index
          text = "#{picked ? chosen : other} #{option[1]}"
          paint = picked && !@disabled ? lit : Style::DEFAULT

          if across
            view.write left, 0, text, paint
            left += item_width(option) + SPACING
          else
            break if position >= view.height

            view.write 0, position, Unicode.truncate(text, view.width, view.policy), paint
          end
        end
      end
    end
  end
end
