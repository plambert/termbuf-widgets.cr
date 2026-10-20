require "../../message"
require "../../router"
require "../../widget"
require "../depth"
require "../display/attached"
require "../field"
require "../label"
require "../panel"
require "../scrolls"
require "./button"
require "./button_group"
require "./interactive"
require "./text_area"
require "./validated_field"
require "./validators"
require "./form/choice"
require "./form/color"
require "./form/parts"
require "./form/rows"
require "./form/schema"

module TermBuf::Widgets
  # Sections of labeled rows in a scrolling window, each row a label and one
  # input. It is built from a schema, so an application can describe its
  # settings as data.
  #
  #     form = Form.new actions: false
  #     form.section "Display" do |section|
  #       section.toggle "motion", "Animate the panels", value: true,
  #         help: "Panels slide and fade. Off draws the end state at once."
  #       section.choice "bars", "Bar color", %w[gradient bands], value: "gradient"
  #     end
  #     form.section "Input" do |section|
  #       section.number "wheel", "Cells per wheel notch", value: 3, range: 1..10
  #       section.text "name", "Tester name", value: "anonymous"
  #       section.color "accent", "Accent", Color.rgb(0x3080C0)
  #       section.action "keys", "Key bindings", hint: "Enter to open"
  #     end
  #     root.add form
  #     form.attach app
  #
  # A form can also be built by hand from widgets with `#add`, each held to a
  # list of rules:
  #
  #     form = Form.new
  #     form.add "name", ValidatedField.new, [Validators.required]
  #     form.add "port", ValidatedField.new, [Validators.numeric]
  #
  # Rows given outside any `#section` go in an unnamed section at the top.
  #
  # ### Values
  #
  # `#values` answers each row's value by key, typed as a `Value`, and
  # `#texts` answers each as a string. `form["motion"]` reads one, and
  # `form["motion"] = false` sets it and sends nothing. Every change a person
  # makes to a schema row emits `Changed` with the key and the new value. An
  # action row holds no value. Pressing it emits `Activated` with its key.
  #
  # ### Colors
  #
  # A color row draws a `ColorSwatch`, and `Enter`, `Space` or a click opens a
  # `ColorPicker` over the form. See `ColorRow` for where it opens and how it
  # closes. The picker opens on the application's screen, so a form with
  # color rows is given the application with `#attach`. `#depth` is how many
  # colors every color row offers unless the row names its own.
  #
  # ### Layout
  #
  # A section is a header drawn across the width in `#header_style`, then its
  # rows, with a blank line before the next section. The labels are squared up
  # to the widest. A form narrower than `#narrow` puts each label above its
  # input. `#label_position` forces either.
  #
  # The rows scroll in a window with a scrollbar on its right, which draws
  # only while the rows are taller than the window. Under the window, the
  # help and the note of the row with the keyboard are wrapped to the width.
  # They take as many rows as the longest help and note of any row, so the
  # window stays put as the keyboard moves. They are left out of a form
  # where no row has either.
  #
  # A form is `Layout::Sizing.grow` tall by default, as every scrolling
  # widget in this shard is, so it takes the room its parent has left. A
  # parent sized `fit` counts a growing child at its floor, which for a form
  # is the first section header and its first row. Give a form in a parent
  # that fits, such as a dialog or an overlay sized to its content,
  # `height: Layout::Sizing.fit`. It is then as tall as its rows, and
  # scrolls when the parent's `max` is shorter than that.
  #
  # ### Keys
  #
  # `Space` and `Enter` toggle a toggle row and move a choice row on one.
  # `Enter` and `Space` press an action row. `Up` and `Down` move between
  # rows and stop at the ends. `Tab` and
  # `Shift+Tab` move through the focus ring. `Home` and `End` go to the first
  # and last row, except on a text row, where they move the cursor, and on a
  # number row, where they go to the ends of its range. `PageUp` and
  # `PageDown` move a window's worth. The form binds them in its own keymap,
  # so an application can rebind them. Whatever else a row's widget binds, it
  # keeps.
  #
  # A binding on a printable key fires before the row's widget sees the key.
  # The form drops its own bindings on a key the row with the keyboard takes
  # as text, so `j` bound on the form still types a `j` into a text row. A
  # host that binds printable keys around the form asks `#typing?` or hands
  # the key over with `#type`.
  #
  # ### Handing it over
  #
  # A form built with `actions: true`, the default, has a `Submit` and a
  # `Cancel` button under the window. `#submit` asks every rule there is: the
  # ones given to `#add` for that field, whatever a `ValidatedField` holds
  # itself to, and the form's own `#rules`, which are asked about all the
  # texts at once. Nothing refused means `Submitted`, carrying a text per key.
  # Anything refused means `Invalid`, carrying the messages per label, with
  # the keyboard put on the first field that has one. A summary line naming
  # every refused field is drawn under the window while `#summary?`.
  #
  # `#submit_on_enter?` makes `Enter` in any field do what `Submit` does. It is
  # on by default for a form with buttons and off for one without.
  class Form < Widget
    include Attached
    include Interactive
    include Schema

    # Where the label sits against the widget it names.
    enum LabelPosition
      # Beside it, in a row.
      Left

      # Above it, in a column.
      Above
    end

    # A rule about the form as a whole, asked with every text at once.
    alias Rule = Proc(Hash(String, String), String?)

    # The key a `#rules` message is filed under in `Invalid#errors`, which is
    # no field's label because it belongs to none of them.
    WHOLE = ""

    # The form was handed over and every rule was happy with it.
    struct Submitted < Message
      # Which form it was.
      getter form : Form

      # What each row held, as text.
      getter values : Hash(String, String)

      def initialize(@form : Form, @values : Hash(String, String))
      end
    end

    # The form was handed over and something was refused. Sent instead of
    # `Submitted`, never as well as it.
    struct Invalid < Message
      # Which form it was.
      getter form : Form

      # What was refused, by label, in the order the rules were asked.
      # `Form::WHOLE` holds whatever the form's own rules said.
      getter errors : Hash(String, Array(String))

      def initialize(@form : Form, @errors : Hash(String, Array(String)))
      end

      # The label of the first field that was refused, or `nil` when only the
      # form's own rules were.
      def first_field : String?
        @errors.each_key { |label| return label unless label == WHOLE }

        nil
      end
    end

    # The form was given up on.
    struct Cancelled < Message
      # Which form it was.
      getter form : Form

      def initialize(@form : Form)
      end
    end

    # A person changed the value of a row.
    struct Changed < Message
      # Which form it was.
      getter form : Form

      # The row's key.
      getter key : String

      # What the row now holds.
      getter value : Value

      def initialize(@form : Form, @key : String, @value : Value)
      end
    end

    # A person pressed an action row.
    struct Activated < Message
      # Which form it was.
      getter form : Form

      # The row's key.
      getter key : String

      def initialize(@form : Form, @key : String)
      end
    end

    # What the two buttons say.
    SUBMIT = "Submit"

    # :ditto:
    CANCEL = "Cancel"

    # The sections, the unnamed one first.
    getter sections = [] of Section

    # What the rules last said, by label. Empty until `#submit` has asked them.
    getter errors = {} of String => Array(String)

    # The line the summary is drawn on.
    @notice : Label

    # The line the help is drawn on.
    @help_line : HelpLine

    # The window the rows scroll in.
    getter fields : Window

    # The scrollbar beside it.
    getter scrollbar : Bar

    # The two buttons, or `nil` for a form built with `actions: false`.
    getter buttons : ButtonGroup?

    # Where a label sits against the widget it names, or `nil` to put it
    # beside the widget unless the form is narrower than `#narrow`.
    getter label_position : LabelPosition?

    # Cells the form has to be narrower than for its labels to go above.
    layout_property narrow : Int32 = 24

    # Cells the label column is given, or `nil` to square it up against the
    # longest label.
    #
    # The automatic width is measured under
    # `TermBuf::Unicode::WidthPolicy::DEFAULT` rather than under the tree's
    # own, because a label is added before there is a tree to ask. Set this on
    # a form whose labels hold glyphs the terminal measures differently.
    getter label_width : Int32? = nil

    # Rules about the form as a whole, asked with every text at once.
    property rules = [] of Rule

    # Whether `Enter` in a field hands the form over.
    property? submit_on_enter : Bool

    # Whether the line naming every refused field is drawn.
    property? summary : Bool

    # What that line is drawn in.
    property error_style : Style

    # What a section header is drawn in.
    getter header_style : Style

    # What the help line is drawn in.
    property help_style : Style

    # What the note under it is drawn in.
    property note_style : Style

    # How many rows to keep in view around the row with the keyboard.
    property scroll_margin : Scrolls::Margin = Scrolls::Margin.rows(1)

    # How many colors a color row offers unless it names its own depth.
    getter depth : Depth

    # The z a color row's picker opens at unless the row names its own, or
    # `nil` to open it above the overlays the form sits in.
    property picker_z : Int32?

    # What a widget the form does not otherwise know contributes as text, or
    # `nil` for one that contributes nothing. Set this to take in a widget of
    # your own.
    property value_of : Proc(Widget, String?)? = nil

    def initialize(actions : Bool = true,
                   label_position : LabelPosition? = nil,
                   submit_on_enter : Bool? = nil,
                   summary : Bool = true,
                   gap : Int32 = 0,
                   submit_text : String = SUBMIT,
                   cancel_text : String = CANCEL,
                   error_style : Style = Style::DEFAULT.fg(Color::RED),
                   header_style : Style = Style::DEFAULT.bold.underlined,
                   help_style : Style = Style::DEFAULT.italic,
                   note_style : Style = Style::DEFAULT.bold,
                   narrow : Int32 = 24,
                   depth : Depth = Depth::TrueColor,
                   picker_z : Int32? = nil,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow,
                   style : Style? = nil)
      @label_position = label_position
      @submit_on_enter = submit_on_enter.nil? ? actions : submit_on_enter
      @summary = summary
      @error_style = error_style
      @header_style = header_style
      @help_style = help_style
      @note_style = note_style
      @narrow = narrow
      @depth = depth
      @picker_z = picker_z
      @width = width
      @height = height
      @style = style
      @direction = Layout::Direction::Column

      @fields = Window.new
      @fields.gap = gap
      @scrollbar = Bar.new @fields
      body = Panel.new direction: Layout::Direction::Row, width: Layout::Sizing.grow
      body.add @fields, @scrollbar

      @help_line = HelpLine.new
      @help_line.hidden = true
      @notice = Label.new
      @notice.height = Layout::Sizing.fit min: 1
      @notice.hidden = true

      @help_line.form = self
      add body, @help_line, @notice
      if actions
        group = ButtonGroup.new [submit_text, cancel_text], gap: 1
        @buttons = group
        add group
      end

      @sections << Section.new(self, nil)
      self.keymap = Form.row_keys self
    end

    # ------------------------------------------------------- the rows

    # Adds a field called *label*, held to *validators*, and answers the entry
    # that was made for it. It goes in the unnamed section at the top.
    def add(label : String, widget : Widget,
            validators : Array(Validator)? = nil, help : String? = nil) : Entry
      attach(Entry.new(label, widget, validators || [] of Validator, help), top).as(Entry)
    end

    # Adds *row* to the unnamed section at the top.
    def add_row(row : Row) : Row
      attach row, top
    end

    # The section called *name*, made the first time it is asked for, after
    # the ones already there. Yields it to be filled in.
    def section(name : String, & : Section ->) : Section
      found = section name
      yield found
      found
    end

    # :ditto:
    def section(name : String) : Section
      found = @sections.find { |section| section.name == name }
      return found if found

      made = Section.new self, name
      @sections << made
      rebuild
      made
    end

    # :nodoc:
    def attach(row : Row, section : Section) : Row
      raise ArgumentError.new "a row with the key #{row.key.inspect} is already here" if row(row.key)

      row.join self
      section.rows << row
      rebuild
      square_up
      refresh_help
      row
    end

    # The unnamed section rows go in when no section is named.
    private def top : Section
      @sections.first
    end

    # Every row, in the order they are drawn.
    def rows : Array(Row)
      @sections.flat_map &.rows
    end

    # The rows built by `#add`.
    def entries : Array(Entry)
      rows.compact_map &.as?(Entry)
    end

    # The row filed under *key*, or `nil` when there is none.
    def row(key : String) : Row?
      @sections.each do |section|
        found = section.rows.find { |candidate| candidate.key == key }
        return found if found
      end

      nil
    end

    # The entry called *label*, or `nil` when there is none.
    def entry(label : String) : Entry?
      row(label).as?(Entry)
    end

    # The widget taking the input for *label*, or `nil` when there is none.
    def widget(label : String) : Widget?
      entry(label).try &.widget
    end

    # Whether the form has a `Submit` and a `Cancel` button.
    def actions? : Bool
      !@buttons.nil?
    end

    # The button that hands the form over. Raises on a form without buttons.
    def submit_button : Button
      group = @buttons
      raise ArgumentError.new "this form has no buttons" unless group

      group.buttons[0]
    end

    # The button that gives up on it. Raises on a form without buttons.
    def cancel_button : Button
      group = @buttons
      raise ArgumentError.new "this form has no buttons" unless group

      group.buttons[1]
    end

    # Turns the row filed under *key* on or off. A row that is off is dimmed
    # and skipped by the keyboard.
    def enable(key : String, on : Bool = true) : Nil
      found = row key
      raise KeyError.new "no row with the key #{key.inspect}" unless found

      found.enabled = on
    end

    # Gives the row filed under *key* a note, drawn under its help, or takes
    # it away with `nil`.
    def note(key : String, text : String?) : Nil
      found = row key
      raise KeyError.new "no row with the key #{key.inspect}" unless found

      found.note = text
    end

    # Forces where the labels sit, or leaves it to the form's width with `nil`.
    def label_position=(position : LabelPosition?) : LabelPosition?
      @label_position = position
      square_up
      invalidate_layout
      position
    end

    # Sets the width of the label column, or squares it up with `nil`.
    def label_width=(width : Int32?) : Int32?
      @label_width = width
      square_up
      width
    end

    # Offers *depth* in every color row that does not name its own.
    def depth=(depth : Depth) : Depth
      @depth = depth
      rows.each { |row| row.as?(ColorRow).try &.refresh_depth }
      depth
    end

    # Sets what the section headers are drawn in.
    def header_style=(style : Style) : Style
      @header_style = style
      @sections.each { |section| section.header.try &.style=(style) }
      style
    end

    # Whether the labels sit above the inputs as the form is laid out now.
    #
    # Asked by each row at every layout. A form that has not been laid out yet
    # has no width to be narrow at, and puts them beside.
    def labels_above? : Bool
      case @label_position
      in LabelPosition::Left  then false
      in LabelPosition::Above then true
      in Nil
        width = @rect.width
        width > 0 && width < @narrow
      end
    end

    # The highest z of the overlays the form sits in, or `nil` for a form in
    # none.
    def overlay_z : Int32?
      found : Int32? = nil
      holder = parent
      while holder
        if holder.is_a? Overlay
          z = holder.z
          found = z if found.nil? || z > found
        end
        holder = holder.parent
      end
      found
    end

    # Lays the window out again from the sections.
    private def rebuild : Nil
      @fields.clear
      first = true

      @sections.each do |section|
        header = section.header
        next if header.nil? && section.rows.empty?

        @fields.add Panel.new(height: Layout::Sizing.fixed(1)) unless first
        first = false

        if header
          header.style = @header_style
          @fields.add header
        end

        section.rows.each { |row| @fields.add row.pair }
      end
    end

    # Gives every label the same width, so that the inputs beside them line up.
    private def square_up : Nil
      wanted = @label_width || widest_label
      rows.each { |row| row.caption.width = Layout::Sizing.fixed wanted }
    end

    private def widest_label : Int32
      rows.max_of? do |row|
        Unicode.string_width row.label, Unicode::WidthPolicy::DEFAULT
      end || 0
    end

    # Shows the help line when any row has help or a note, and lays it out
    # again for the text it now holds.
    #
    # :nodoc:
    def refresh_help : Nil
      all = rows
      @help_line.hidden = all.none?(&.note) && all.none?(&.help)
      @help_line.invalidate_layout
    end

    # *widget* if the keyboard can land on it, and otherwise the first thing
    # under it that it can.
    def self.focusable_in(widget : Widget) : Widget?
      return if widget.hidden?
      return widget if widget.focusable?

      widget.children.each do |child|
        found = focusable_in child
        return found if found
      end

      nil
    end

    # ------------------------------------------------------- the values

    # What each row holds, by key. An action row has no entry, and neither
    # does an `#add` row whose widget holds no text.
    def values : Hash(String, Value)
      found = {} of String => Value

      rows.each do |row|
        value = row.value
        found[row.key] = value unless value.nil?
      end

      found
    end

    # What each row holds as text, by key. What `Submitted` carries and what
    # `#rules` are asked about.
    #
    # A `Field`, a `TextArea` and anything built on either answers its text.
    # Any other widget given to `#add` answers through `#value_of`, or is left
    # out.
    def texts : Hash(String, String)
      found = {} of String => String

      rows.each do |row|
        text = row.text
        found[row.key] = text if text
      end

      found
    end

    # What the row filed under *key* holds, or `nil` for no such row or one
    # that holds nothing.
    def [](key : String) : Value?
      row(key).try &.value
    end

    # Sets what the row filed under *key* holds, and draws it. Sends nothing.
    def []=(key : String, value : Value) : Value
      found = row key
      raise KeyError.new "no row with the key #{key.inspect}" unless found

      found.value = value
      invalidate_layout
      value
    end

    # What *widget* holds as text, or `nil` when it holds none.
    def text_of(widget : Widget) : String?
      case widget
      when Field    then widget.text
      when TextArea then widget.text
      else               @value_of.try &.call(widget)
      end
    end

    # ------------------------------------------------------ handing it over

    # Every rule's answer, by label. Empty when the form is ready to go.
    def validate : Hash(String, Array(String))
      found = {} of String => Array(String)

      entries.each do |entry|
        messages = errors_of entry
        found[entry.label] = messages unless messages.empty?
      end

      collected = texts
      whole = @rules.compact_map &.call(collected)
      found[WHOLE] = whole unless whole.empty?

      found
    end

    # Every rule *entry* is held to, its own included.
    def errors_of(entry : Entry) : Array(String)
      text = text_of(entry.widget) || ""
      messages = entry.validators.compact_map &.call(text)

      field = entry.widget.as? ValidatedField
      messages.concat field.validate if field

      messages
    end

    # Hands the form over, or says why it cannot be.
    #
    # *context* is what a handler is holding when a button was pressed. Without
    # one the router is found the way `Widget#emit` finds its mailbox, so a
    # form submitted from application code still moves the keyboard onto the
    # field that was refused.
    def submit(context : Context? = nil) : Nil
      found = validate
      show_summary found

      if found.empty?
        emit Submitted.new self, texts
        return
      end

      reveal found, context
      emit Invalid.new self, found
    end

    # Gives up on the form.
    def cancel : Nil
      emit Cancelled.new self
    end

    # Takes the summary line away, which is what a form being filled in again
    # wants.
    def clear_errors : Nil
      show_summary({} of String => Array(String))
    end

    # Puts the keyboard on the first field that was refused.
    private def reveal(found : Hash(String, Array(String)), context : Context?) : Nil
      label = Invalid.new(self, found).first_field
      return unless label

      refused = entry label
      return unless refused

      wanted = refused.target
      return unless wanted

      stack = context ? context.focus : routed_by.try &.focus
      stack.try &.focus(wanted)
      bring refused
    end

    # -------------------------------------------------------- the summary

    # The line drawn under the fields, or `nil` when there is nothing to say.
    def summary_text : String?
      return if @errors.empty?

      @errors.compact_map do |label, messages|
        message = messages.first?
        next unless message

        label.empty? ? message : "#{label}: #{message}"
      end.join "; "
    end

    private def show_summary(found : Hash(String, Array(String))) : Nil
      @errors = found
      text = @summary ? summary_text : nil

      @notice.text = text || ""
      @notice.style = @error_style
      @notice.hidden = text.nil?
    end

    # ------------------------------------------------------- the keyboard

    # The row the keyboard is on, or `nil` when it is somewhere else.
    def focused_row : Row?
      row_holding routed_by.try(&.focus.current)
    end

    private def row_holding(held : Widget?) : Row?
      return unless held

      rows.find &.focused?(held)
    end

    # Whether *key* is one a person types as text: a character with no
    # `Ctrl`, `Alt` or `Super` held.
    def self.printable?(key : Key) : Bool
      key.character? && !key.ctrl? && !key.alt? && !key.super?
    end

    # Whether the row with the keyboard takes free text, as a text row does.
    #
    # A binding on a printable key fires before the row's widget sees the
    # key. A host that binds one, such as `j` to move down, asks this or
    # `#type` first so that the letter still goes into a text row.
    def typing? : Bool
      focused_row.try(&.typing?) || false
    end

    # Whether the row with the keyboard takes *key* as text. A number row
    # takes digits, and a text row takes every printable key.
    def types?(key : Key) : Bool
      focused_row.try(&.types?(key)) || false
    end

    # Hands the key *context* is answering to the row with the keyboard when
    # the row takes it as text. Answers whether it did.
    #
    #     map.bind Key.parse("j"), "the row below",
    #       ->(context : Context) { form.step_row 1, context unless form.type context }
    def type(context : Context) : Bool
      event = context.event
      return false unless event.is_a? Events::Key

      row = focused_row
      return false unless row && row.types?(event.key)

      row.press event.key
      context.consume
      true
    end

    # The form's bindings, less any on a printable key the row with the
    # keyboard takes as text, which the row's widget gets instead.
    def keymap : Bindings?
      bound = super
      row = focused_row
      return bound unless bound && row

      typed = bound.bindings.select { |binding| row.types? binding.keys.first }
      return bound if typed.empty?

      kept = Bindings.new
      bound.bindings.each { |binding| kept.bind binding unless typed.includes? binding }
      kept
    end

    # The keys that move between rows, bound on *form* so an application can
    # rebind them.
    def self.row_keys(form : Form) : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Up"), "the row before", ->(context : Context) { form.step_row(-1, context) }
        map.bind Key.parse("Down"), "the row after", ->(context : Context) { form.step_row 1, context }
        map.bind Key.parse("Tab"), "the next control", ->(context : Context) { form.tab 1, context }
        map.bind Key.parse("Shift+Tab"), "the control before",
          ->(context : Context) { form.tab(-1, context) }
        map.bind Key.parse("Home"), "the first row", ->(context : Context) { form.end_row(-1, context) }
        map.bind Key.parse("End"), "the last row", ->(context : Context) { form.end_row 1, context }
        map.bind Key.parse("PageUp"), "a window back", ->(context : Context) { form.page(-1, context) }
        map.bind Key.parse("PageDown"), "a window on", ->(context : Context) { form.page 1, context }
      end
    end

    # The rows the keyboard can land on, in order.
    def reachable : Array(Row)
      rows.select &.focusable?
    end

    # Moves the keyboard *step* rows along, stopping at either end. From a
    # button under the window, `Up` goes to the last row.
    def step_row(step : Int32, context : Context) : Nil
      return if kept? context

      among = reachable
      return if among.empty?

      current = focused_row
      position = current ? among.index(&.same?(current)) : nil
      wanted = if position
                 among[(position + step).clamp(0, among.size - 1)]
               elsif step < 0 && focus_within?
                 among.last
               end
      land wanted, current, context if wanted
    end

    # Moves the keyboard through the focus ring, and brings the row it lands
    # on into view.
    def tab(step : Int32, context : Context) : Nil
      focused_row.try &.leave
      step > 0 ? context.focus.next : context.focus.previous
      landed = focused_row
      bring landed if landed
    end

    # Goes to the first row for a negative *step* and the last for a positive
    # one, unless the row with the keyboard keeps the key.
    def end_row(step : Int32, context : Context) : Nil
      return if kept? context

      among = reachable
      wanted = step < 0 ? among.first? : among.last?
      land wanted, focused_row, context if wanted
    end

    # Scrolls a window's worth towards *step* and puts the keyboard on the
    # row that comes into view there.
    def page(step : Int32, context : Context) : Nil
      return if kept? context

      among = reachable
      return if among.empty?

      current = focused_row || among.first
      from = @fields.top_of(current.pair) || 0
      reach = from + step * @fields.page
      wanted = if step > 0
                 among.reverse.find { |row| (@fields.top_of(row.pair) || 0) <= reach }
               else
                 among.find { |row| (@fields.top_of(row.pair) || 0) >= reach }
               end
      wanted = neighbor(among, current, step) if wanted.nil? || wanted.same?(current)

      @fields.scroll_by dy: step * @fields.page
      land wanted, current, context
    end

    private def neighbor(among : Array(Row), current : Row, step : Int32) : Row
      position = among.index(&.same?(current)) || 0
      among[(position + step).clamp(0, among.size - 1)]
    end

    # Whether the row with the keyboard keeps the key being answered, in
    # which case it has been handed over.
    private def kept?(context : Context) : Bool
      event = context.event
      return false unless event.is_a? Events::Key

      current = focused_row
      return false unless current && current.keeps?(event.key)

      current.press event.key
      true
    end

    # Puts the keyboard on *row*, letting *from* go first.
    private def land(row : Row, from : Row?, context : Context) : Nil
      target = row.target
      return unless target

      from.try { |left| left.leave unless left.same?(row) }
      context.focus.focus target
      bring row
    end

    # Scrolls the window as little as it takes to show *row*.
    def bring(row : Row) : Nil
      @fields.bring row.pair, @scroll_margin
    end

    # What a click on a row's label does.
    #
    # :nodoc:
    def click(row : Row, context : Context) : Nil
      return unless row.enabled?

      focused_row.try { |current| current.leave unless current.same?(row) }
      row.click context
    end

    # ------------------------------------------------------------- events

    # Takes `Enter` on a row whose widget left it alone, a button press, a
    # line handed over by a field, and the messages that mean a row changed.
    def handle(event : Event, context : Context) : Nil
      case event
      when Events::Key
        entered_row event, context
      when Button::Pressed
        pressed event, context
      when Field::Accepted
        restore event, context.target
        entered context
      when ValidatedField::Invalid
        entered context
      when Dialog::Closed
        context.consume if rows.any? { |row| row.as?(ColorRow).try &.owns?(event.dialog) }
      else
        changed event, context
      end
    end

    # `Enter` on a toggle or a choice row does what `Space` does there.
    private def entered_row(event : Events::Key, context : Context) : Nil
      return unless event.key.is? Key::Name::Enter
      return unless event.key.modifiers.none?

      row = focused_row
      context.consume if row && row.enter
    end

    private def pressed(event : Button::Pressed, context : Context) : Nil
      button = event.button
      group = @buttons

      if group && button.same?(group.buttons[0])
        context.consume
        submit context
      elsif group && button.same?(group.buttons[1])
        context.consume
        cancel
      elsif found = rows.find { |row| row.is_a?(ActionRow) && row.pressed?(event) }
        context.consume
        emit Activated.new(self, found.key)
      end
    end

    # A message from a row's widget that changed its value becomes a `Changed`.
    private def changed(event : Event, context : Context) : Nil
      return unless event.is_a? Message

      rows.each do |row|
        value = row.heard event
        next if value.nil?

        context.consume
        emit Changed.new(self, row.key, value)
        return
      end
    end

    # A line handed over in one of the fields hands the whole form over, which
    # is what `Enter` means in a dialog of one or two fields.
    #
    # The field's own message is left alone rather than claimed. It says what
    # happened to that line, and an application watching one field is entitled
    # to hear it.
    private def entered(context : Context) : Nil
      submit context if @submit_on_enter
    end

    # Puts an accepted line back in the field it came out of.
    #
    # `Editor` clears the buffer when it accepts, which is right for a prompt
    # that asks again and wrong here. The value has to still be in the form
    # when the form is read, and on the screen when the user looks at it. The
    # field is found from `Context#target`, which for a message is the
    # emitter's parent, so a field nested inside a widget of its own is still
    # matched to the row it belongs to.
    private def restore(event : Field::Accepted, target : Widget?) : Nil
      return unless target

      found = rows.find { |row| target.under? row.pair }
      return unless found

      field = Form.focusable_in(found.input).as? Field
      return unless field && field.text.empty?

      field.text = event.text
    end
  end
end
