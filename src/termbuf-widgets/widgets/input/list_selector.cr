require "../../message"
require "../../router"
require "../../widget"
require "../panel"
require "../split"
require "./button"
require "./button_group"
require "./selection_list"

module TermBuf::Widgets
  # Two lists and the buttons for moving options between them.
  #
  #     selector = ListSelector.new Option.all(%w[read write execute])
  #     root.add selector
  #
  # What is on the left is what may be picked; what is on the right is what has
  # been. `Space` and `Enter` on a row send it across, and so does a click on
  # it, because the only thing a row in either list is for is going to the
  # other one. The buttons do the same for whatever the keyboard is on, and the
  # doubled ones do it for the lot.
  #
  # `Tab` moves between the parts rather than between every control in them:
  # the two lists and the column of buttons are three places to be, and a tab
  # order that stopped at each button separately would take five presses to
  # cross a widget that has three things in it. The arrows move within the
  # column, the way they do in any `ButtonGroup`.
  #
  # ### Ordering
  #
  # `#ordering` adds a second column of buttons on the far side, which move the
  # row the keyboard is on up and down the chosen list. Without it the chosen
  # list stays in the order things were sent across.
  #
  # ### What it says
  #
  # `Changed` carries the chosen values, in the order the right-hand list holds
  # them, and is sent for every move however it was made. The lists' own
  # messages are claimed rather than passed on: a selector speaks for its
  # lists.
  class ListSelector(T) < Widget
    # The chosen values changed.
    struct Changed(V) < Message
      # The selector it happened in.
      getter selector : Widget

      # What is now chosen, in the order the right-hand list holds it.
      getter values : Array(V)

      def initialize(@selector : Widget, @values : Array(V))
      end
    end

    # What the four buttons between the lists say.
    LABELS = {add: ">", remove: "<", add_all: ">>", remove_all: "<<"}

    # What the two ordering buttons say.
    ORDER_LABELS = {up: "^", down: "v"}

    # The list of what may be chosen.
    getter available : SelectionList(T)

    # The list of what has been.
    getter chosen : SelectionList(T)

    # The column of buttons between them.
    getter buttons : ButtonGroup

    # The column that moves a chosen row up and down, or `nil` on a selector
    # that does not order.
    getter order : ButtonGroup? = nil

    # The two panes and the rule between them.
    getter split : Split

    def initialize(options : Array(Option(T)) = [] of Option(T),
                   chosen : Array(Option(T)) = [] of Option(T),
                   ordering : Bool = false,
                   at : Int32? = nil,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow,
                   style : Style? = nil)
      @width = width
      @height = height
      @style = style

      @available = SelectionList(T).new options
      @chosen = SelectionList(T).new chosen
      @buttons = ButtonGroup.new direction: Layout::Direction::Column, gap: 0
      LABELS.each_value { |label| @buttons.add label }

      right = Panel.new direction: Layout::Direction::Row,
        width: Layout::Sizing.grow, height: Layout::Sizing.grow
      right.add @buttons, @chosen

      if ordering
        column = ButtonGroup.new direction: Layout::Direction::Column, gap: 0
        ORDER_LABELS.each_value { |label| column.add label }
        @order = column
        right.add column
      end

      @split = Split.new @available, right, at: at
      add @split
      self.keymap = tabbing
    end

    # ------------------------------------------------------- the buttons

    # The button that sends the row the keyboard is on across.
    def add_button : Button
      @buttons.buttons[0]
    end

    # The one that sends it back.
    def remove_button : Button
      @buttons.buttons[1]
    end

    # The one that sends every option across.
    def add_all_button : Button
      @buttons.buttons[2]
    end

    # The one that sends every one of them back.
    def remove_all_button : Button
      @buttons.buttons[3]
    end

    # The button that moves a chosen row up, or `nil` without `#ordering`.
    def up_button : Button?
      @order.try &.buttons[0]?
    end

    # The one that moves it down.
    def down_button : Button?
      @order.try &.buttons[1]?
    end

    # ------------------------------------------------------- the values

    # What may still be chosen, in the order the left-hand list holds it.
    def available_values : Array(T)
      @available.options.map &.value
    end

    # What has been chosen, in the order the right-hand list holds it.
    def chosen_values : Array(T)
      @chosen.options.map &.value
    end

    # Sets what is chosen, taking each of *wanted* out of whichever list holds
    # it. Says nothing: this is the application filling the form in.
    def chosen_values=(wanted : Array(T)) : Array(T)
      everything = @available.options + @chosen.options
      taken = wanted.compact_map { |value| everything.find { |option| option.value == value } }
      left = everything.reject { |option| wanted.includes? option.value }

      @available.options = left
      @chosen.options = taken
      wanted
    end

    # ------------------------------------------------------- moving them

    # Sends the row the keyboard is on, or whatever is marked, across.
    def add_chosen : Nil
      transfer @available, @chosen, moving(@available)
    end

    # Sends it back.
    def remove_chosen : Nil
      transfer @chosen, @available, moving(@chosen)
    end

    # Sends everything across.
    def add_all : Nil
      transfer @available, @chosen, available_values
    end

    # Sends everything back.
    def remove_all : Nil
      transfer @chosen, @available, chosen_values
    end

    # Moves the chosen row the keyboard is on *step* places along the list.
    def reorder(step : Int32) : Nil
      index = @chosen.current_index
      return unless index

      wanted = index + step
      return unless 0 <= wanted < @chosen.options.size

      shuffled = @chosen.options.dup
      shuffled.swap index, wanted
      @chosen.options = shuffled
      @chosen.highlight wanted
      announce
    end

    # What a button acting on *list* acts on: whatever is marked, or the row
    # the keyboard is on when nothing is.
    private def moving(list : SelectionList(T)) : Array(T)
      marked = list.values
      return marked unless marked.empty?

      option = list.current
      option ? [option.value] : [] of T
    end

    private def transfer(from : SelectionList(T), to : SelectionList(T),
                         values : Array(T)) : Nil
      moved = values.compact_map do |value|
        from.options.find { |option| option.value == value }
      end
      return if moved.empty?

      moved.each { |option| from.remove_value option.value }
      to.options = to.options + moved
      from.clear_selection
      announce
    end

    private def announce : Nil
      emit Changed(T).new(self, chosen_values)
    end

    # ------------------------------------------------------------- events

    # Takes what a list or a button said and turns it into a move.
    def handle(event : Event, context : Context) : Nil
      case event
      when SelectionList::Changed(T)
        context.consume
        event.list.same?(@available) ? add_chosen : remove_chosen
      when SelectionList::Confirmed(T), SelectionList::Refused(T)
        # A confirmation follows the change that `Enter` already made, and a
        # refusal cannot happen on a list with no cap. Both are claimed so
        # that neither reaches the application as a second move.
        context.consume
      when Button::Pressed
        pressed event.button, context
      end
    end

    private def pressed(button : Button, context : Context) : Nil
      case
      when button.same? add_button        then add_chosen
      when button.same? remove_button     then remove_chosen
      when button.same? add_all_button    then add_all
      when button.same? remove_all_button then remove_all
      when button.same? up_button         then reorder(-1)
      when button.same? down_button       then reorder 1
      else                                     return
      end

      context.consume
    end

    # ------------------------------------------------------------- focus

    # The parts `Tab` moves between, in order.
    def stops : Array(Widget)
      found = [@available, @buttons, @chosen] of Widget
      column = @order
      found << column if column
      found
    end

    # Where the keyboard lands when `Tab` reaches *stop*.
    def entry_of(stop : Widget) : Widget?
      return @available.list if stop.same? @available
      return @chosen.list if stop.same? @chosen

      group = stop.as? ButtonGroup
      group.try &.buttons.find(&.focusable?)
    end

    # Moves the keyboard *step* parts along, wrapping at either end.
    def step_stop(context : Context, step : Int32) : Nil
      parts = stops
      held = context.focus.current
      at = held ? parts.index { |part| held.under? part } : nil
      at = step > 0 ? -1 : 0 unless at

      wanted = entry_of parts[(at + step) % parts.size]
      context.focus.focus wanted if wanted
    end

    private def tabbing : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Tab"), "the next part",
          ->(context : Context) { step_stop context, 1 }
        map.bind Key.parse("Shift+Tab"), "the part before",
          ->(context : Context) { step_stop context, -1 }
      end
    end
  end
end
