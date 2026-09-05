require "../../message"
require "../../router"
require "../../widget"
require "./interactive"

module TermBuf::Widgets
  # A label with padding that says when it has been pressed.
  #
  #     button = Button.new "Save"
  #     root.add button
  #
  # `Enter` and `Space` press it while it has the keyboard, and so does a click
  # that goes down and comes up again inside it. Either way it emits `Pressed`,
  # and whatever contains it decides what pressing it means:
  #
  #     def handle(event : Event, context : Context) : Nil
  #       return unless event.is_a? Button::Pressed
  #
  #       save if event.button.same? @save
  #       context.consume
  #     end
  #
  # A disabled button is out of the tab order and answers neither the keyboard
  # nor the pointer, but it is still drawn: a control that vanishes when it
  # cannot be used tells the user less than one that is visibly unavailable.
  class Button < Widget
    include Interactive

    # The button was pressed. Carries the button, since one handler usually
    # answers several.
    struct Pressed < Message
      # Which button it was.
      getter button : Button

      def initialize(@button : Button)
      end
    end

    # The keys that press a button while it has the keyboard.
    PRESS_KEYS = {"Enter", "Space"}

    # What the button says.
    layout_property text : String = ""

    # Whether the button refuses the keyboard and answers nothing.
    #
    # A layout property because focusability is part of what a frame has to
    # settle: `App#frame` rebuilds the tab order whenever the tree says its
    # geometry is stale, and a button that has just been disabled has to leave
    # the ring in the same frame.
    layout_property? disabled : Bool = false

    # Whether this is the chosen one of a `ButtonGroup` acting as a radio set.
    # Styling only; the group is what keeps it true of one button at a time.
    property? selected : Bool = false

    # Which side of the button the text sits on when it is wider than the text.
    property align : Unicode::Align = Unicode::Align::Center

    # What the button is drawn in when nothing else applies.
    property normal_style : Style = Style::DEFAULT

    # What it is drawn in while it has the keyboard.
    property focused_style : Style = Style::DEFAULT.reverse

    # What it is drawn in while the pointer is held down on it.
    property pressed_style : Style = Style::DEFAULT.reverse.bold

    # What it is drawn in while it is selected.
    property selected_style : Style = Style::DEFAULT.bold

    # What it is drawn in while it is disabled.
    property disabled_style : Style = Style::DEFAULT.faint

    def initialize(@text : String = "",
                   padding : Layout::Padding = Layout::Padding.new(0, 1, 0, 1),
                   disabled : Bool = false,
                   border : Border? = nil,
                   style : Style? = nil)
      @disabled = disabled
      @padding = padding
      @border = border
      @style = style
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fixed 1
      self.keymap = press_bindings
    end

    # The keys that press this button.
    private def press_bindings : Bindings
      Bindings.build do |map|
        PRESS_KEYS.each do |key|
          map.bind Key.parse(key), "press the button",
            ->(_context : Context) { press; nil }
        end
      end
    end

    # Focus lands here unless the button is disabled.
    def focusable? : Bool
      !@disabled
    end

    # Says the button was pressed. Does nothing while it is disabled.
    def press : Nil
      return if @disabled

      emit Pressed.new self
    end

    # Takes a click, and swallows whatever is aimed at a disabled button.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      # A disabled button is still a button as far as the pointer is
      # concerned: a click on it does nothing rather than falling through to
      # whatever is behind it.
      return context.consume if @disabled && frame.contains?(event.x, event.y)

      clicked event, context do
        take_focus context
        press
      end
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      wanted = Unicode.string_width @text, policy
      Layout::Intrinsic.new Math.min(wanted, 1), wanted
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      1
    end

    # ------------------------------------------------------------ drawing

    # What the button is drawn in as it stands, the widget's own style under
    # whatever its state adds.
    #
    # The renderer reads this before `#draw` and fills the ground with it, so
    # a button changes colour whole rather than only under its text.
    def style : Style?
      base = @style || Style::DEFAULT
      base.merge state_style
    end

    # The part of the style the button's state decides.
    def state_style : Style
      return @disabled_style if @disabled
      return @pressed_style if held?
      return @focused_style if focused?
      return @selected_style if @selected

      @normal_style
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0 || @text.empty?

      shown = Unicode.truncate @text, view.width, view.policy
      view.write column_for(shown, view), 0, shown
    end

    private def column_for(shown : String, view : View) : Int32
      room = view.width - Unicode.string_width(shown, view.policy)
      return 0 if room <= 0

      case @align
      in .left?   then 0
      in .right?  then room
      in .center? then room // 2
      end
    end
  end
end
