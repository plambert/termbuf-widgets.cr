require "../../message"
require "../../router"
require "../../widget"
require "../label"
require "../rows"
require "../virtual_list"
require "./checkbox"
require "./interactive"

module TermBuf::Widgets
  # A label and the value it stands for.
  #
  # What a list shows and what an application gets back are rarely the same
  # thing: a row reading "Pacific/Auckland" stands for a time zone object, and
  # the widget has no business turning one into the other. An option carries
  # both, so the list draws the label and answers the value.
  record Option(T), label : String, value : T do
    # An option labelled with whatever the value says of itself.
    def self.of(value : T) : Option(T)
      new value.to_s, value
    end

    # One option per value, each labelled by `#to_s`.
    def self.all(values : Enumerable(T)) : Array(Option(T))
      values.map { |value| Option(T).of value }
    end
  end

  # A window over options, with a mark against the ones that are chosen.
  #
  #     list = SelectionList.new Option.all(%w[email sms post]), mode: :multi
  #     root.add list
  #
  # `Space` marks the row the keyboard is on and `Enter` hands the choice over.
  # Either way the list says what it now holds: `Changed` at every change and
  # `Confirmed` when the choice is handed over.
  #
  # What is on screen is a `VirtualList`, which the list holds as its one
  # child, so only the rows in the window are ever drawn. The options
  # themselves are held in declaration order and never reordered: filtering
  # builds a map from the rows that are showing to the options behind them,
  # which is what lets a selection survive a filter that hides it and come
  # back when the filter is cleared.
  #
  # ### How many may be chosen
  #
  # `Mode::Single` keeps one, the way a menu does: choosing a second lets the
  # first go. `Mode::Multi` keeps as many as `#max_selections` allows, and a
  # choice beyond that is refused rather than quietly dropping the oldest —
  # the list says `Refused` and stays as it was.
  #
  # ### Filtering
  #
  # A `#filterable?` list takes what is typed at it as a prefix filter over the
  # labels, and `Backspace` takes a character back off. The filter is shown
  # above the rows while there is one, so a list that has stopped answering
  # the keyboard says why.
  #
  # ### Glyphs
  #
  # The marks are `Checkbox`'s, measured under the tree's own
  # `TermBuf::Unicode::WidthPolicy` before they are used: a box-drawing tick is
  # one cell on a terminal that measures it the way the standard says and two
  # on one that does not, and every row after it would be indented by a cell
  # too many.
  class SelectionList(T) < Widget
    include Interactive

    # How many options may be chosen at once.
    enum Mode
      # One, the way a menu works: a second choice lets the first go.
      Single

      # As many as `SelectionList#max_selections` allows.
      Multi
    end

    # The choice changed. Sent for every change, however it was made.
    struct Changed(V) < Message
      # The list it happened in.
      getter list : Widget

      # What is now chosen, in the order the options were declared.
      getter values : Array(V)

      def initialize(@list : Widget, @values : Array(V))
      end
    end

    # The choice was handed over, which is what `Enter` means.
    struct Confirmed(V) < Message
      # The list it came from.
      getter list : Widget

      # What was chosen, in the order the options were declared.
      getter values : Array(V)

      def initialize(@list : Widget, @values : Array(V))
      end
    end

    # A choice was put back because it would have gone past the cap.
    struct Refused(V) < Message
      # The list that refused it.
      getter list : Widget

      # The option that was not taken.
      getter option : Option(V)

      # The cap it would have broken.
      getter max : Int32

      def initialize(@list : Widget, @option : Option(V), @max : Int32)
      end

      # The value that was not taken.
      def value : V
        @option.value
      end
    end

    # The keys a list answers on top of the window's own.
    TOGGLE = "Space"

    # :ditto:
    CONFIRM = "Enter"

    # The options, in the order they were given.
    getter options : Array(Option(T))

    # The window the rows are shown through, which is this list's one child.
    # What a `Scrollbar` attaches to.
    getter list : VirtualList(Option(T))

    # How many options may be chosen at once.
    property mode : Mode

    # The most that may be chosen, or `nil` for as many as there are. Ignored
    # in `Mode::Single`, which is a cap of one by definition.
    property max_selections : Int32?

    # Whether what is typed at the list filters it.
    property? filterable : Bool

    # The marks to draw, or `nil` to measure and choose.
    property marks : Checkbox::Marks? = nil

    # What the row the keyboard is on is drawn in.
    property selected_style : Style = Style::DEFAULT.reverse

    # What the filter line is drawn in.
    property filter_style : Style = Style::DEFAULT.faint

    # What marks a label cut short at the right edge.
    property ellipsis : String = "…"

    # What draws one row, or `nil` for the default, which writes the mark and
    # the label.
    property on_draw : Proc(View, Int32, Option(T), Bool, Nil)? = nil

    # The prefix the labels are held to, or an empty string for none.
    getter filter : String = ""

    # Which options are chosen, as indices into `#options`.
    @chosen = Set(Int32).new

    # The options that are showing, filled in place rather than replaced so
    # that the `Rows` the window was given can hold the array itself and never
    # this list.
    @shown = [] of Option(T)

    # Where each showing row sits in `#options`.
    @indices = [] of Int32

    # The line the filter is drawn on.
    @notice : Label

    def initialize(options : Array(Option(T)) = [] of Option(T),
                   mode : Mode = Mode::Single,
                   max_selections : Int32? = nil,
                   filterable : Bool = false,
                   marks : Checkbox::Marks? = nil,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow(min: 1),
                   style : Style? = nil)
      @options = options
      @mode = mode
      @max_selections = max_selections
      @filterable = filterable
      @marks = marks
      @width = width
      @height = height
      @style = style
      @direction = Layout::Direction::Column

      shown = @shown
      rebuild_rows

      @notice = Label.new
      @notice.hidden = true

      @list = VirtualList(Option(T)).new Rows(Option(T)).from(-> { shown.size },
        ->(index : Int32) { shown[index] })
      @list.on_draw = ->(view : View, index : Int32, option : Option(T), chosen : Bool) do
        paint view, index, option, chosen
      end

      add @notice, @list
      self.keymap = choosing
    end

    # ------------------------------------------------------- the options

    # Replaces the options, keeping nothing: a new set of options is a new
    # question, and a choice made against the old one means nothing.
    def options=(options : Array(Option(T))) : Array(Option(T))
      @options = options
      @chosen.clear
      refilter
      options
    end

    # Adds *option* at the end and answers it.
    def add_option(option : Option(T)) : Option(T)
      @options << option
      refilter
      option
    end

    # :ditto:
    def add_option(label : String, value : T) : Option(T)
      add_option Option(T).new(label, value)
    end

    # Takes the option holding *value* out, along with any choice of it.
    def remove_value(value : T) : Option(T)?
      index = @options.index { |option| option.value == value }
      return unless index

      taken = @options.delete_at index
      renumber index
      refilter
      taken
    end

    # How many options there are, filter or no filter.
    def size : Int32
      @options.size
    end

    # The options that are showing, in the order they are drawn.
    def shown : Array(Option(T))
      @shown
    end

    # ----------------------------------------------------- the selection

    # What is chosen, in the order the options were declared.
    def values : Array(T)
      chosen_options.map &.value
    end

    # :ditto:
    def chosen_options : Array(Option(T))
      @chosen.to_a.sort!.compact_map { |index| @options[index]? }
    end

    # Whether *value* is chosen.
    def selected?(value : T) : Bool
      index = @options.index { |option| option.value == value }
      !index.nil? && @chosen.includes?(index)
    end

    # Chooses *value*, answering whether it went.
    #
    # Nothing is said: a message is what the user did, and this is the
    # application saying what the state is. `#toggle` is the one that speaks.
    #
    # NOTE: `#select` chooses a value; moving the keyboard from row to row is
    # `#highlight`. The window under this one spells the second one `#select`,
    # and a list where the same word meant both would be a list where
    # `select(0)` did one thing on `Array(String)` and the other on
    # `Array(Int32)`.
    def select(value : T) : Bool
      index = @options.index { |option| option.value == value }
      return false unless index
      return true if @chosen.includes? index
      return false unless room_for?

      @chosen.clear if @mode.single?
      @chosen << index
      true
    end

    # Lets *value* go.
    def deselect(value : T) : Nil
      index = @options.index { |option| option.value == value }
      @chosen.delete index if index
    end

    # Lets everything go. The options stay; `Widget#clear`, which takes the
    # children out, is a different thing and is left alone.
    def clear_selection : Nil
      @chosen.clear
    end

    # Sets what is chosen outright, as far as the options allow. Says nothing,
    # and enforces no cap: this is the application filling the form in.
    def values=(wanted : Array(T)) : Array(T)
      @chosen.clear
      wanted.each do |value|
        index = @options.index { |option| option.value == value }
        @chosen << index if index
      end
      wanted
    end

    # ------------------------------------------------------- the keyboard

    # Which row the keyboard is on, counting the rows that are showing.
    def selected : Int32
      @list.selected
    end

    # Puts the keyboard on row *index* of what is showing, and brings it into
    # view. The window's own `VirtualList#select`, under the name that leaves
    # `#select` free for choosing a value.
    def highlight(index : Int32) : Nil
      @list.select index
    end

    # The option the keyboard is on, or `nil` when nothing is showing.
    def current : Option(T)?
      @shown[@list.selected]?
    end

    # Where the option the keyboard is on sits in `#options`, or `nil` when
    # nothing is showing.
    def current_index : Int32?
      @indices[@list.selected]?
    end

    # Puts the keyboard on the row showing *value*, answering whether it was
    # there to be found.
    def highlight_value(value : T) : Bool
      row = @shown.index { |option| option.value == value }
      return false unless row

      highlight row
      true
    end

    # ------------------------------------------------------------ choosing

    # Chooses the option the keyboard is on, or lets it go, and says so.
    def toggle_current : Nil
      index = current_index
      toggle index if index
    end

    # Chooses the option at *index* of `#options`, or lets it go, and says so.
    def toggle(index : Int32) : Nil
      option = @options[index]?
      return unless option

      if @chosen.includes? index
        @chosen.delete index
        announce
        return
      end

      unless room_for?
        emit Refused(T).new self, option, @max_selections || 1
        return
      end

      @chosen.clear if @mode.single?
      @chosen << index
      announce
    end

    # Hands the choice over, which is what `Enter` means.
    #
    # A single-choice list with nothing chosen takes the row the keyboard is
    # on, since arriving at a row and pressing `Enter` is how a menu is used.
    def confirm : Nil
      if @mode.single? && @chosen.empty?
        index = current_index
        if index
          @chosen << index
          announce
        end
      end

      emit Confirmed(T).new(self, values)
    end

    # Whether one more choice fits.
    private def room_for? : Bool
      return true if @mode.single?

      limit = @max_selections
      return true unless limit

      @chosen.size < limit
    end

    private def announce : Nil
      emit Changed(T).new(self, values)
    end

    # -------------------------------------------------------- the filter

    # Holds the labels to those beginning with *text*, ignoring case.
    def filter=(text : String) : String
      return text if text == @filter

      @filter = text
      refilter
      text
    end

    # Works the showing rows out again, keeping the keyboard on the option it
    # was on when that option is still showing.
    def refilter : Nil
      wanted = current_index
      rebuild_rows

      row = wanted ? @indices.index(wanted) : nil
      @list.select(row || Math.min(@list.selected, Math.max(@shown.size - 1, 0)))
      show_filter
      invalidate_layout
    end

    # Whether *label* is one the filter keeps.
    private def kept?(label : String) : Bool
      return true if @filter.empty?

      label.downcase.starts_with? @filter.downcase
    end

    private def rebuild_rows : Nil
      @shown.clear
      @indices.clear

      @options.each_with_index do |option, index|
        next unless kept? option.label

        @shown << option
        @indices << index
      end
    end

    # The filter line, which is there only while there is a filter to show.
    private def show_filter : Nil
      @notice.text = "/#{@filter}"
      @notice.style = @filter_style
      @notice.hidden = @filter.empty?
    end

    # Moves every chosen index past *removed* down one, so the set still names
    # the options it named before one was taken out.
    private def renumber(removed : Int32) : Nil
      moved = Set(Int32).new

      @chosen.each do |index|
        next if index == removed

        moved << (index > removed ? index - 1 : index)
      end

      @chosen = moved
    end

    # ------------------------------------------------------------- events

    # Takes what was typed at a filtering list, and a click on a row.
    def handle(event : Event, context : Context) : Nil
      case event
      when Events::Key   then typed event.key, context
      when Events::Mouse then pointed event, context
      end
    end

    # A character is a longer filter and `Backspace` is a shorter one.
    # Anything else is somebody else's.
    private def typed(key : Key, context : Context) : Nil
      return unless @filterable

      if key.name.backspace?
        return if @filter.empty?

        context.consume
        self.filter = @filter[0, @filter.size - 1]
        return
      end

      return unless key.character? && (key.modifiers & ~Modifiers::Shift).none?
      return if key.char < ' '

      context.consume
      self.filter = @filter + key.char
    end

    # A click puts the keyboard on the row and chooses it.
    private def pointed(event : Events::Mouse, context : Context) : Nil
      clicked event, context do
        take_focus context
        row = row_at event.y
        next unless row

        highlight row
        toggle_current
      end
    end

    # Which showing row (*y*) falls on, or `nil` for a point off the rows.
    def row_at(y : Int32) : Int32?
      box = @list.content
      return unless box.height > 0

      row = y - box.y + @list.scroll
      return unless 0 <= (y - box.y) < box.height
      return unless 0 <= row < @shown.size

      row
    end

    private def choosing : Bindings
      Bindings.build do |map|
        map.bind Key.parse(TOGGLE), "choose this row",
          ->(_context : Context) { toggle_current }
        map.bind Key.parse(CONFIRM), "hand the choice over",
          ->(_context : Context) { confirm }
      end
    end

    # ------------------------------------------------------------ drawing

    # The marks this list draws with under *policy*: the pair it was given, or
    # whichever spelling suits the terminal.
    def marks_for(policy : Unicode::WidthPolicy) : Checkbox::Marks
      @marks || Checkbox.marks_for(policy)
    end

    # Draws one row of the window, which is what the window was handed when it
    # was built.
    private def paint(view : View, index : Int32, option : Option(T), chosen : Bool) : Nil
      hook = @on_draw
      return hook.call view, index, option, chosen if hook

      source = @indices[index]?
      picked = !source.nil? && @chosen.includes?(source)
      text = "#{marks_for(view.policy).for picked} #{option.label}"

      view.write 0, 0, Unicode.ellipsize(text, view.width, @ellipsis, view.policy),
        chosen ? @selected_style : Style::DEFAULT
    end
  end
end
