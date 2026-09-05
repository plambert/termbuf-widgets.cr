require "../../message"
require "../../router"
require "../../widget"
require "./checkbox"
require "./interactive"

module TermBuf::Widgets
  # A column of `Checkbox`es answering one question, and the rule for how many
  # of them may be ticked.
  #
  #     group = CheckboxGroup.new %w[email sms post], min: 1, max: 2
  #     root.add group
  #
  # Up and down move between the boxes and `Space` ticks the one that has the
  # keyboard. A toggle that would take the group past `#max`, or below `#min`,
  # is put back the way it was and the group emits `Refused` instead of
  # `Changed`: the alternative is a group that quietly ticks a fourth box in a
  # set of three, and a user who finds out at submission time.
  #
  # The bounds hold what the user does, not what the application does.
  # `#values=` sets the state outright, the way a form filled in from a record
  # does, and says nothing.
  class CheckboxGroup < Widget
    include Stepping

    # Why a toggle was put back.
    enum Reason
      # Ticking it would have taken the group past `CheckboxGroup#max`.
      Max

      # Unticking it would have taken the group below `CheckboxGroup#min`.
      Min
    end

    # A box in the group was ticked or unticked.
    struct Changed < Message
      # The group it happened in.
      getter group : CheckboxGroup

      # Which box, counting from zero.
      getter index : Int32

      # The box itself.
      getter checkbox : Checkbox

      # What it now says.
      getter? checked : Bool

      def initialize(@group : CheckboxGroup, @index : Int32, @checkbox : Checkbox,
                     @checked : Bool)
      end
    end

    # A toggle was put back because it would have broken the group's bounds.
    struct Refused < Message
      # The group that refused it.
      getter group : CheckboxGroup

      # Which box, counting from zero.
      getter index : Int32

      # The box itself, back the way it was.
      getter checkbox : Checkbox

      # Which bound it would have broken.
      getter reason : Reason

      def initialize(@group : CheckboxGroup, @index : Int32, @checkbox : Checkbox,
                     @reason : Reason)
      end
    end

    # The fewest boxes the user may leave ticked.
    property min : Int32

    # The most the user may tick, or `nil` for as many as there are.
    property max : Int32?

    def initialize(items : Enumerable(String) | Enumerable({String, Bool}) = [] of String,
                   direction : Layout::Direction = Layout::Direction::Column,
                   gap : Int32 = 0,
                   @min : Int32 = 0,
                   @max : Int32? = nil,
                   style : Style? = nil)
      @direction = direction
      @gap = gap
      @style = style

      items.each do |item|
        case item
        in String              then add Checkbox.new(item)
        in Tuple(String, Bool) then add Checkbox.new(item[0], checked: item[1])
        end
      end

      rebind
    end

    # The boxes in the group, in the order they were added.
    def boxes : Array(Checkbox)
      @children.compact_map &.as?(Checkbox)
    end

    # Adds a box saying *label* and answers it.
    def add(label : String, checked : Bool = false) : Checkbox
      box = Checkbox.new label, checked: checked
      add box
      box
    end

    # What each box says, in order.
    def values : Array(Bool)
      boxes.map &.checked?
    end

    # Sets what each box says, as far as there are boxes to set.
    #
    # Says nothing and enforces nothing: this is the application filling the
    # form in, and the bounds are about what the user is allowed to do to it.
    def values=(states : Array(Bool)) : Array(Bool)
      boxes.each_with_index { |box, index| box.checked = states[index]? || false }
      states
    end

    # What each box is for, in order.
    def labels : Array(String)
      boxes.map &.text
    end

    # The labels of the boxes that are ticked.
    def checked_labels : Array(String)
      boxes.select(&.checked?).map &.text
    end

    # How many boxes are ticked.
    def count : Int32
      boxes.count &.checked?
    end

    # Rebinding the arrows, because which pair moves within the group depends
    # on which way the group runs.
    def direction=(value : Layout::Direction) : Layout::Direction
      result = super
      rebind
      result
    end

    # Takes what a box said, holds it against the bounds, and says what came of
    # it.
    #
    # The box's own `Checkbox::Changed` is claimed rather than passed on: the
    # group speaks for its boxes, and a refused toggle that also arrived as a
    # change would be a change that did not happen.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Checkbox::Changed

      index = boxes.index &.same?(event.checkbox)
      return unless index

      context.consume
      reason = refusal event.checked?

      if reason
        event.checkbox.checked = !event.checked?
        emit Refused.new self, index, event.checkbox, reason
      else
        emit Changed.new self, index, event.checkbox, event.checked?
      end
    end

    # Which bound the group has just broken, or `nil` for a toggle it can keep.
    #
    # Asked after the box has already turned over, so the count is the one the
    # group would be left with.
    private def refusal(checked : Bool) : Reason?
      total = count
      limit = @max

      return Reason::Max if checked && limit && total > limit
      return Reason::Min if !checked && total < @min

      nil
    end

    private def rebind : Nil
      self.keymap = arrow_keymap @direction
    end
  end
end
