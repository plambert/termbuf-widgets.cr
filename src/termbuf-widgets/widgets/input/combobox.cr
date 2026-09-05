require "../../layout/floating"
require "../../message"
require "../../router"
require "../../widget"
require "../field"
require "./selection_list"

module TermBuf::Widgets
  # A field with a list of options under it, narrowed by what is typed.
  #
  #     box = Combobox.new Option.all(%w[amber azure beige])
  #     root.add box
  #
  # Typing filters the list and opens it; `Up` and `Down` move through it
  # without the keyboard ever leaving the field, `Enter` takes the highlighted
  # option, and `Escape` shuts it again. What comes of it is `Chosen`, carrying
  # the value behind the label.
  #
  # The list is a `SelectionList` floating under the field, anchored to it with
  # `Layout::Overflow::Flip`, so a box near the bottom of the screen opens
  # upward instead of off the edge. It is a child of the combobox and hidden
  # while it is shut, which keeps it out of the layout, out of the tab order
  # and out of the hit test all at once.
  #
  # ### Text that is not an option
  #
  # `#allow_custom?` decides what `Enter` does when nothing is highlighted. A
  # box that allows it says `Chosen` with a `nil` value and `Chosen#custom?`
  # true, which is what a field offering suggestions rather than a closed set
  # wants. A box that does not stays where it is and says nothing: there is
  # nothing to report, and clearing the entry would throw away work.
  class Combobox(T) < Widget
    # A field that says when its text changed.
    #
    # `Field` speaks when a line is handed over, which is the wrong moment
    # here: the list has to narrow while the line is still being typed. This
    # is the smallest thing that says so, and it says it to a proc rather than
    # as a message, because a message would arrive a pump later than the key
    # that caused it.
    class Entry < Field
      # Called after any key or paste that changed the text.
      property on_change : Proc(Nil)? = nil

      def press(key : Key) : Nil
        before = text
        super
        @on_change.try &.call unless text == before
      end

      def paste(text : String) : Nil
        before = self.text
        super
        @on_change.try &.call unless self.text == before
      end
    end

    # An option was taken, or text that is not one was accepted.
    struct Chosen(V) < Message
      # Which box it came from.
      getter combobox : Widget

      # The value behind the label, or `nil` for text that is not an option.
      getter value : V?

      # What the field holds now.
      getter text : String

      def initialize(@combobox : Widget, @value : V?, @text : String)
      end

      # Whether this is text of the user's own rather than one of the options.
      def custom? : Bool
        @value.nil?
      end
    end

    # The field the text is typed into.
    getter field : Entry

    # The drop-down, which is this box's floating child.
    getter list : SelectionList(T)

    # Whether text that is not one of the options is accepted.
    property? allow_custom : Bool

    # Rows the drop-down may grow to.
    getter max_visible : Int32

    def initialize(options : Array(Option(T)) = [] of Option(T),
                   prompt : Field::Prompt? = nil,
                   placeholder : String? = nil,
                   allow_custom : Bool = false,
                   max_visible : Int32 = 6,
                   border : Border? = nil,
                   list_border : Border? = nil,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   style : Style? = nil)
      @allow_custom = allow_custom
      @max_visible = max_visible
      @width = width
      @height = Layout::Sizing.fit
      @style = style
      @direction = Layout::Direction::Column

      @field = Entry.new prompt: prompt, placeholder: placeholder, border: border
      @list = SelectionList(T).new options, height: Layout::Sizing.fit(max: max_visible)
      @list.border = list_border
      @list.show_filter = false
      @list.list.height = Layout::Sizing.fit max: max_visible
      @list.hidden = true
      @list.floating = Layout::Floating.on @field,
        element: Layout::AttachPoint::LeftTop,
        parent: Layout::AttachPoint::LeftBottom,
        overflow: Layout::Overflow::Flip

      add @field, @list
      @field.on_change = -> { narrow }
      self.keymap = walking
    end

    # ------------------------------------------------------------- state

    # Whether the drop-down is showing.
    def open? : Bool
      !@list.hidden?
    end

    # The options, in the order they were given.
    def options : Array(Option(T))
      @list.options
    end

    # Replaces the options and shuts the drop-down, since a new set of options
    # is a new question.
    def options=(options : Array(Option(T))) : Array(Option(T))
      close
      @list.options = options
    end

    # What the field holds.
    def text : String
      @field.text
    end

    # :ditto:
    def text=(entered : String) : String
      @field.text = entered
    end

    # The value behind the text, or `nil` when the text is nobody's label.
    def value : T?
      option = options.find { |candidate| candidate.label == @field.text }
      option.try &.value
    end

    # ---------------------------------------------------------- opening it

    # Shows the drop-down, unless there is nothing in it to show.
    def open : Nil
      return if @list.shown.empty?

      @list.hidden = false
    end

    # Shuts it, and forgets the filter so that opening it again shows
    # everything rather than whatever the last search left.
    def close : Nil
      return unless open?

      @list.hidden = true
      @list.filter = ""
    end

    # Narrows the drop-down to what the field holds, opening it when there is
    # anything to show and shutting it when there is not.
    def narrow : Nil
      @list.filter = @field.text
      @list.shown.empty? ? shut : open
    end

    # `#close` without the filter being forgotten, which is what narrowing to
    # nothing wants: the next keystroke narrows again from where it was.
    private def shut : Nil
      @list.hidden = true
    end

    # ------------------------------------------------------------ choosing

    # Moves the highlight *step* rows, opening the drop-down first when it is
    # shut. The keyboard stays in the field throughout.
    #
    # Opening it this way shows whatever the filter last left, which after a
    # choice is everything: somebody who has taken one option and reached for
    # the arrows is looking for a different one, not for the one they already
    # have.
    def step(step : Int32) : Nil
      unless open?
        return unless step > 0

        open
        return
      end

      @list.highlight @list.selected + step
    end

    # Takes the highlighted option, or the text as it stands.
    def take : Nil
      option = open? ? @list.current : nil
      return choose option if option
      return unless @allow_custom

      close
      emit Chosen(T).new(self, nil, @field.text)
    end

    # Puts *option* in the field, shuts the drop-down, and says so.
    def choose(option : Option(T)) : Nil
      @field.text = option.label
      @list.clear_selection
      close
      emit Chosen(T).new(self, option.value, option.label)
    end

    # Shuts the drop-down, or gives up on the line when it is already shut.
    def dismiss : Nil
      return close if open?

      @field.press Key.named(Key::Name::Escape)
    end

    # ------------------------------------------------------------- events

    # Takes what the drop-down said and turns it into a choice.
    #
    # The list's own messages are claimed rather than passed on: a combobox
    # speaks for its list, and an application that had to answer both would
    # have to know which one meant what.
    def handle(event : Event, context : Context) : Nil
      case event
      when SelectionList::Changed(T)
        context.consume
        chosen = event.values.first?
        take_value chosen if chosen
      when SelectionList::Confirmed(T), SelectionList::Refused(T)
        context.consume
      end
    end

    private def take_value(value : T) : Nil
      option = options.find { |candidate| candidate.value == value }
      choose option if option
    end

    private def walking : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Down"), "the option after", ->(_context : Context) { step 1 }
        map.bind Key.parse("Up"), "the option before", ->(_context : Context) { step(-1) }
        map.bind Key.parse("Enter"), "take this option", ->(_context : Context) { take }
        map.bind Key.parse("Escape"), "shut the drop-down", ->(_context : Context) { dismiss }
      end
    end
  end
end
