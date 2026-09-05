require "../../message"
require "../../router"
require "../../widget"
require "../field"
require "../label"
require "../panel"
require "./button"
require "./button_group"
require "./interactive"
require "./text_area"
require "./validated_field"
require "./validators"

module TermBuf::Widgets
  # Labelled fields in a column, and what becomes of them when they are handed
  # over.
  #
  #     form = Form.new
  #     form.add "name", ValidatedField.new, [Validators.required]
  #     form.add "port", ValidatedField.new, [Validators.numeric]
  #     root.add form
  #
  # Each `#add` builds a pair — a `Label` and the widget — laid out across or
  # down according to `#label_position`, and appends it to the column. `Tab`
  # visits them in the order they were declared, because that is the order they
  # sit in the tree and the focus ring is built by walking it.
  #
  # ### Handing it over
  #
  # `#submit` asks every rule there is: the ones given to `#add` for that
  # field, whatever a `ValidatedField` holds itself to, and the form's own
  # `#rules`, which are asked about all the values at once and are where a rule
  # like "the end date is after the start date" belongs. Nothing refused means
  # `Submitted`, carrying a value per label; anything refused means `Invalid`,
  # carrying the messages per label, with the keyboard put on the first field
  # that has one.
  #
  # The buttons are a `Submit` and a `Cancel`, and `#submit_on_enter?` makes
  # `Enter` in any field do what the first of them does.
  #
  # ### What is shown
  #
  # A `ValidatedField` draws its own message under its own line, so the form
  # does not draw one too. What the form adds is the summary: one line naming
  # every field that was refused, drawn under the fields while `#summary?` and
  # there is anything to say.
  class Form < Widget
    include Interactive

    # Where the label sits against the widget it names.
    enum LabelPosition
      # Beside it, in a row.
      Left

      # Above it, in a column.
      Above
    end

    # A rule about the form as a whole, asked with every value at once.
    alias Rule = Proc(Hash(String, String), String?)

    # The key a `#rules` message is filed under in `Invalid#errors`, which is
    # no field's label because it belongs to none of them.
    WHOLE = ""

    # The form was handed over and every rule was happy with it.
    struct Submitted < Message
      # Which form it was.
      getter form : Form

      # What each labelled field held.
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

    # One labelled field: what it is called, what takes the input, the rules it
    # is held to, and the pair the two of them were laid out in.
    class Entry
      # What the field is called, which is the key its value comes back under.
      getter label : String

      # What takes the input.
      getter widget : Widget

      # The rules this field is held to.
      getter validators : Array(Validator)

      # The label and the widget, laid out together.
      getter pair : Panel

      # The label itself, so that a column of them can be squared up.
      getter caption : Label

      def initialize(@label : String, @widget : Widget,
                     @validators : Array(Validator), @pair : Panel,
                     @caption : Label)
      end
    end

    # What the two buttons say.
    SUBMIT = "Submit"

    # :ditto:
    CANCEL = "Cancel"

    # The labelled fields, in the order they were declared.
    getter entries = [] of Entry

    # What the rules last said, by label. Empty until `#submit` has asked them.
    getter errors = {} of String => Array(String)

    # The line the summary is drawn on.
    @notice : Label

    # The column the pairs sit in.
    getter fields : Panel

    # The two buttons.
    getter actions : ButtonGroup

    # Where a label sits against the widget it names.
    getter label_position : LabelPosition

    # Cells the label column is given, or `nil` to square it up against the
    # longest label.
    #
    # The automatic width is measured under
    # `TermBuf::Unicode::WidthPolicy::DEFAULT` rather than under the tree's
    # own, because a label is added before there is a tree to ask. Set this on
    # a form whose labels hold glyphs the terminal measures differently.
    property label_width : Int32? = nil

    # Rules about the form as a whole, asked with every value at once.
    property rules = [] of Rule

    # Whether `Enter` in a field hands the form over.
    property? submit_on_enter : Bool

    # Whether the line naming every refused field is drawn.
    property? summary : Bool

    # What that line is drawn in.
    property error_style : Style

    def initialize(label_position : LabelPosition = LabelPosition::Left,
                   submit_on_enter : Bool = true,
                   summary : Bool = true,
                   gap : Int32 = 0,
                   submit_text : String = SUBMIT,
                   cancel_text : String = CANCEL,
                   error_style : Style = Style::DEFAULT.fg(Color::RED),
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.fit,
                   style : Style? = nil)
      @label_position = label_position
      @submit_on_enter = submit_on_enter
      @summary = summary
      @error_style = error_style
      @width = width
      @height = height
      @style = style
      @direction = Layout::Direction::Column

      @fields = Panel.new direction: Layout::Direction::Column, gap: gap,
        width: Layout::Sizing.grow
      @notice = Label.new
      @notice.hidden = true
      @actions = ButtonGroup.new [submit_text, cancel_text], gap: 1

      add @fields, @notice, @actions
    end

    # ------------------------------------------------------- the fields

    # Adds a field called *label*, held to *validators*, and answers the entry
    # that was made for it.
    def add(label : String, widget : Widget,
            validators : Array(Validator)? = nil) : Entry
      caption = Label.new label, wrap: Layout::Wrap::None
      pair = Panel.new direction: pair_direction,
        gap: @label_position.left? ? 1 : 0,
        width: Layout::Sizing.grow
      pair.add caption, widget

      entry = Entry.new label, widget, validators || [] of Validator, pair, caption
      @entries << entry
      @fields.add pair
      square_up
      entry
    end

    # The entry called *label*, or `nil` when there is none.
    def entry(label : String) : Entry?
      @entries.find { |found| found.label == label }
    end

    # The widget taking the input for *label*, or `nil` when there is none.
    def widget(label : String) : Widget?
      entry(label).try &.widget
    end

    # The button that hands the form over.
    def submit_button : Button
      @actions.buttons[0]
    end

    # The button that gives up on it.
    def cancel_button : Button
      @actions.buttons[1]
    end

    private def pair_direction : Layout::Direction
      case @label_position
      in .left?  then Layout::Direction::Row
      in .above? then Layout::Direction::Column
      end
    end

    # Gives every label the same width, so that the fields beside them line up.
    private def square_up : Nil
      return unless @label_position.left?

      wanted = @label_width || widest_label
      @entries.each { |entry| entry.caption.width = Layout::Sizing.fixed wanted }
    end

    private def widest_label : Int32
      @entries.max_of? do |entry|
        Unicode.string_width entry.label, Unicode::WidthPolicy::DEFAULT
      end || 0
    end

    # ------------------------------------------------------- the values

    # What each labelled field holds, by label.
    #
    # A `Field`, a `TextArea` and anything built on either answers its text.
    # Anything else answers through `#value_of`, or is left out.
    def values : Hash(String, String)
      found = {} of String => String

      @entries.each do |entry|
        text = text_of entry.widget
        found[entry.label] = text if text
      end

      found
    end

    # What a widget the form does not otherwise know contributes, or `nil` for
    # one that contributes nothing. Set this to take in a widget of your own.
    property value_of : Proc(Widget, String?)? = nil

    # What *widget* holds, or `nil` when it holds no text.
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

      @entries.each do |entry|
        messages = errors_of entry
        found[entry.label] = messages unless messages.empty?
      end

      collected = values
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
    # *context* is what a handler is holding when a button was pressed; without
    # one the router is found the way `Widget#emit` finds its mailbox, so a
    # form submitted from application code still moves the keyboard onto the
    # field that was refused.
    def submit(context : Context? = nil) : Nil
      found = validate

      if found.empty?
        show_summary found
        emit Submitted.new self, values
        return
      end

      show_summary found
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

      widget = entry(label).try &.widget
      return unless widget

      wanted = focusable_in widget
      return unless wanted

      stack = context ? context.focus : routed_by.try &.focus
      stack.try &.focus(wanted)
    end

    # *widget* if the keyboard can land on it, and otherwise the first thing
    # under it that it can.
    private def focusable_in(widget : Widget) : Widget?
      return widget if widget.focusable?

      widget.children.each do |child|
        found = focusable_in child
        return found if found
      end

      nil
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

    # ------------------------------------------------------------- events

    # Takes a button press, and a line handed over by a field.
    def handle(event : Event, context : Context) : Nil
      case event
      when Button::Pressed
        pressed event.button, context
      when Field::Accepted
        restore event, context.target
        entered context
      when ValidatedField::Invalid
        entered context
      end
    end

    private def pressed(button : Button, context : Context) : Nil
      if button.same? submit_button
        context.consume
        submit context
      elsif button.same? cancel_button
        context.consume
        cancel
      end
    end

    # A line handed over in one of the fields hands the whole form over, which
    # is what `Enter` means in a dialog of one or two fields.
    #
    # The field's own message is left alone rather than claimed: it says what
    # happened to that line, and an application watching one field is entitled
    # to hear it.
    private def entered(context : Context) : Nil
      submit context if @submit_on_enter
    end

    # Puts an accepted line back in the field it came out of.
    #
    # `Editor` clears the buffer when it accepts, which is right for a prompt
    # that asks again and wrong here: the value has to still be in the form
    # when the form is read, and on the screen when the user looks at it. The
    # field is found from `Context#target`, which for a message is the
    # emitter's parent, so a field nested inside a widget of its own is still
    # matched to the entry it belongs to.
    private def restore(event : Field::Accepted, target : Widget?) : Nil
      return unless target

      found = @entries.find { |entry| target.under? entry.pair }
      return unless found

      field = found.widget.as? Field
      return unless field && field.text.empty?

      field.text = event.text
    end
  end
end
