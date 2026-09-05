require "../../message"
require "../../router"
require "../../widget"
require "./button"

module TermBuf::Widgets
  # A row or a column of `Button`s that the arrow keys move between.
  #
  #     group = ButtonGroup.new %w[Yes No Cancel]
  #     root.add group
  #
  # The arrows that move within the group are the ones that run along it: left
  # and right in a row, up and down in a column. Tab still leaves the group,
  # because tab moves between the things on a screen and the group is one of
  # them. A disabled button is stepped over, since it cannot take the keyboard
  # in the first place.
  #
  # An exclusive group is a radio set. Pressing a button in one makes it the
  # chosen one, unmakes whichever was chosen before, and the group emits
  # `Changed`. A group that is not exclusive keeps no choice at all: its
  # buttons are three commands sitting together rather than three answers to
  # one question.
  class ButtonGroup < Widget
    include Stepping

    # The chosen button changed. Only an exclusive group sends one.
    struct Changed < Message
      # The group it happened in.
      getter group : ButtonGroup

      # Which of the group's buttons is now chosen, counting from zero.
      getter index : Int32

      # The button itself.
      getter button : Button

      def initialize(@group : ButtonGroup, @index : Int32, @button : Button)
      end
    end

    # Whether the group acts as a radio set.
    property? exclusive : Bool

    # Which button is chosen, or `nil` for none. Always `nil` on a group that
    # is not exclusive.
    getter selected : Int32? = nil

    def initialize(labels : Enumerable(String) = [] of String,
                   direction : Layout::Direction = Layout::Direction::Row,
                   gap : Int32 = 1,
                   @exclusive : Bool = false,
                   selected : Int32? = nil,
                   style : Style? = nil)
      @direction = direction
      @gap = gap
      @style = style
      labels.each { |label| add Button.new(label) }
      self.selected = selected
      rebind
    end

    # The buttons in the group, in the order they were added.
    def buttons : Array(Button)
      @children.compact_map &.as?(Button)
    end

    # Adds a button saying *label* and answers it.
    def add(label : String) : Button
      button = Button.new label
      add button
      button
    end

    # Chooses the button at *index*, or none for `nil`.
    #
    # Setting the choice does not emit `Changed`: a message says what the user
    # did, and this is the application saying what the state is.
    def selected=(index : Int32?) : Int32?
      list = buttons
      index = nil if index && !(0 <= index < list.size)
      @selected = index
      list.each_with_index { |button, position| button.selected = position == index }
      index
    end

    # The chosen button, or `nil` when none is.
    def selected_button : Button?
      index = @selected
      index ? buttons[index]? : nil
    end

    # Rebinding the arrows, because which pair moves within the group depends
    # on which way the group runs.
    def direction=(value : Layout::Direction) : Layout::Direction
      result = super
      rebind
      result
    end

    # Takes what a button in the group said, and turns it into a choice.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Button::Pressed
      return unless @exclusive

      index = buttons.index &.same?(event.button)
      return if index.nil? || index == @selected

      self.selected = index
      emit Changed.new self, index, event.button
    end

    # Which way the arrows run: along the group.
    private def rebind : Nil
      self.keymap = arrow_keymap @direction
    end
  end
end
