require "../../message"
require "../../router"
require "../../widget"
require "./interactive"

module TermBuf::Widgets
  # A box that is either ticked or not, and a label saying what it means.
  #
  #     box = Checkbox.new "Wrap long lines", checked: true
  #     root.add box
  #
  # `Space` toggles it while it has the keyboard, and so does a click inside
  # it. Either way it emits `Changed` carrying the state it has arrived at.
  #
  # The marks are measured before they are used. A ticked box drawn as `☑` is
  # one cell on a terminal that measures it the way the standard says and two
  # on one that does not, and a checkbox laid out for the first and drawn on
  # the second overflows every row it is on. Rather than guess, the marks are
  # measured under the tree's own `TermBuf::Unicode::WidthPolicy` and the ASCII
  # spelling is used unless the pretty one comes out at a single cell.
  class Checkbox < Widget
    include Interactive

    # The box was ticked or unticked.
    struct Changed < Message
      # Which box it was.
      getter checkbox : Checkbox

      # What it now says.
      getter? checked : Bool

      def initialize(@checkbox : Checkbox, @checked : Bool)
      end
    end

    # The two marks a checkbox is drawn with, one per state.
    record Marks, checked : String, unchecked : String do
      # The mark for *state*.
      def for(state : Bool) : String
        state ? @checked : @unchecked
      end

      # Both marks, for measuring.
      def both : Array(String)
        [@checked, @unchecked]
      end

      # Cells the wider of the two takes under *policy*. The layout reserves
      # this, so a box that is ticked and one that is not are the same width
      # and a column of them does not shuffle sideways as they are answered.
      def width(policy : Unicode::WidthPolicy) : Int32
        both.max_of { |mark| Unicode.string_width mark, policy }
      end
    end

    # What a checkbox is drawn with where the terminal measures them at one
    # cell each.
    UNICODE = Marks.new "☑", "☐"

    # What it is drawn with everywhere else.
    ASCII = Marks.new "[x]", "[ ]"

    # The key that toggles a checkbox. `Enter` is left alone: in a form it
    # belongs to whatever the form does when it is finished.
    TOGGLE = "Space"

    # What the box says it is for.
    layout_property text : String = ""

    # The marks to draw, or `nil` to measure and choose.
    layout_property marks : Marks? = nil

    # Whether the box is ticked.
    #
    # Setting it does not emit `Changed`: a message says what the user did, and
    # this is the application saying what the state is. `#toggle` is the one
    # that speaks.
    property? checked : Bool

    # Whether the box refuses the keyboard and answers nothing.
    layout_property? disabled : Bool = false

    # What the box and its label are drawn in.
    property normal_style : Style = Style::DEFAULT

    # What they are drawn in while the box has the keyboard.
    property focused_style : Style = Style::DEFAULT.reverse

    # What they are drawn in while it is disabled.
    property disabled_style : Style = Style::DEFAULT.faint

    # How clusters are measured, taken from the tree at every layout.
    getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

    def initialize(@text : String = "",
                   @checked : Bool = false,
                   disabled : Bool = false,
                   marks : Marks? = nil,
                   style : Style? = nil)
      @disabled = disabled
      @marks = marks
      @style = style
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fixed 1
      self.keymap = Bindings.build do |map|
        map.bind Key.parse(TOGGLE), "tick the box",
          ->(_context : Context) { toggle; nil }
      end
    end

    # The marks this box is drawn with: the ones it was given, or whichever
    # pair suits the policy the tree was laid out under.
    def marks : Marks
      told = @marks
      return told if told

      Checkbox.marks_for @policy
    end

    # *preferred* where every mark in it measures a single cell under *policy*,
    # and *fallback* otherwise.
    def self.marks_for(policy : Unicode::WidthPolicy,
                       preferred : Marks = UNICODE,
                       fallback : Marks = ASCII) : Marks
      Glyphs.single_cell?(preferred.both, policy) ? preferred : fallback
    end

    # Focus lands here unless the box is disabled.
    def focusable? : Bool
      !@disabled
    end

    # Turns the box over and says so. Does nothing while it is disabled.
    def toggle : Nil
      return if @disabled

      @checked = !@checked
      emit Changed.new self, @checked
    end

    # Takes a click, and swallows whatever is aimed at a disabled box.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse
      return context.consume if @disabled && frame.contains?(event.x, event.y)

      clicked event, context do
        take_focus context
        toggle
      end
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy
      mark = marks.width policy
      wanted = @text.empty? ? mark : mark + 1 + Unicode.string_width(@text, policy)

      Layout::Intrinsic.new mark, wanted
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy
      1
    end

    # ------------------------------------------------------------ drawing

    def style : Style?
      base = @style || Style::DEFAULT
      base.merge state_style
    end

    # The part of the style the box's state decides.
    def state_style : Style
      return @disabled_style if @disabled
      return @focused_style if focused?

      @normal_style
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      set = marks
      mark = set.for @checked
      view.write 0, 0, mark

      left = set.width(view.policy) + 1
      room = view.width - left
      return if @text.empty? || room <= 0

      view.write left, 0, Unicode.truncate(@text, room, view.policy)
    end
  end
end
