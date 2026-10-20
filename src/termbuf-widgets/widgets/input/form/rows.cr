require "../../../widget"
require "../../label"
require "../button"
require "../checkbox"
require "../number_field"
require "../text_area"
require "../validators"
require "./choice"
require "./parts"

module TermBuf::Widgets
  class Form < Widget
    # What a row of the form holds.
    alias Value = Bool | Int32 | String | Color

    # One row of a form, with a key, a label and one input.
    #
    # Each kind of row is a subclass that says what its input is, what value
    # it holds, and which of its widget's messages mean the value changed. A
    # new kind is one more subclass.
    abstract class Row
      # What the row's value is filed under in `Form#values`.
      getter key : String

      # What the label column says.
      getter label : String

      # What the help line says while the row has the keyboard, or `nil`.
      getter help : String?

      # What the line under the help says while the row has the keyboard, or
      # `nil`. For a value that is forced from elsewhere.
      getter note : String?

      # The label as drawn.
      getter caption : Caption

      # The label and the input, laid out together. Set when the row joins a
      # form.
      getter! pair : Pair

      # What the label is drawn in while the row is disabled.
      property disabled_style : Style = Style::DEFAULT.faint

      # Whether the row takes the keyboard.
      getter? enabled : Bool = true

      def initialize(@key : String, @label : String, @help : String? = nil)
        @caption = Caption.new @label
      end

      # The widget in the input column.
      abstract def input : Widget

      # What the row holds, or `nil` for a row that holds nothing.
      abstract def value : Value?

      # Sets what the row holds and draws it. Sends nothing.
      abstract def value=(value : Value) : Value

      # Whether *event*, a message from inside the row, means the value
      # changed. Answers the new value, or `nil` when it does not.
      abstract def heard(event : Event) : Value?

      # What the row holds as text, for `Form#texts`, or `nil` for nothing.
      def text : String?
        value.try &.to_s
      end

      # The widget the keyboard lands on, or `nil` when there is none.
      def target : Widget?
        Form.focusable_in input
      end

      # Whether the keyboard can land on the row.
      def focusable? : Bool
        @enabled && !target.nil?
      end

      # Whether the keyboard is on the row.
      def focused?(held : Widget?) : Bool
        return false unless held

        held.under? input
      end

      # Turns the row on or off. A row that is off is dimmed and out of the
      # tab order.
      def enabled=(on : Bool) : Bool
        @enabled = on
        @caption.style = on ? nil : @disabled_style
        disable_input !on
        on
      end

      # Disables the input. Each kind knows how its widget is disabled.
      def disable_input(off : Bool) : Nil
      end

      # Sets the help and asks the form to make room for it.
      def help=(text : String?) : String?
        @help = text
        @owner.try &.refresh_help
        text
      end

      # Sets the note and asks the form to make room for it.
      def note=(text : String?) : String?
        @note = text
        @owner.try &.refresh_help
        text
      end

      # Whether the input keeps *key* rather than letting the form move between
      # rows with it.
      def keeps?(key : Key) : Bool
        false
      end

      # Whether the input takes free text, so that every printable key typed
      # at it belongs to it.
      def typing? : Bool
        false
      end

      # Whether the input takes *key* as text.
      def types?(key : Key) : Bool
        typing? && Form.printable?(key)
      end

      # Hands a key the row keeps to its input.
      def press(key : Key) : Nil
      end

      # Puts the keyboard on the row and does what the row does when it is
      # pressed. What a click on the label means.
      def click(context : Context) : Nil
        held = target
        context.focus.focus held if held
        activate
      end

      # What pressing the row does, beyond taking the keyboard.
      def activate : Nil
      end

      # Called as the keyboard leaves the row.
      def leave : Nil
      end

      # :nodoc:
      def join(form : Form) : Nil
        @owner = form
        made = Pair.new form, self
        made.add @caption, input
        @pair = made
      end

      @owner : Form? = nil
    end

    # A row built by `Form#add`, with a label and any widget held to a list of
    # rules.
    class Entry < Row
      # What takes the input.
      getter widget : Widget

      # The rules this field is held to.
      getter validators : Array(Validator)

      def initialize(label : String, @widget : Widget, @validators : Array(Validator),
                     help : String? = nil)
        super label, label, help
      end

      def input : Widget
        @widget
      end

      # Disables the widgets in the shard that can be. Any other widget stays
      # as it is, and only the form's own keys skip it.
      def disable_input(off : Bool) : Nil
        case widget = @widget
        when Checkbox, Button, NumberField, TextInput then widget.disabled = off
        end
      end

      # What the widget holds as text, or `nil`.
      def value : Value?
        @owner.try &.text_of(@widget)
      end

      # Sets the text of a `Field` or a `TextArea`. Other widgets are left
      # alone.
      def value=(value : Value) : Value
        case widget = @widget
        when Field    then widget.text = value.to_s
        when TextArea then widget.text = value.to_s
        end
        value
      end

      # A hand-built row says what happened through its widget's own messages.
      def heard(event : Event) : Value?
        nil
      end

      def text : String?
        @owner.try &.text_of(@widget)
      end

      # A field and a text area take free text.
      def typing? : Bool
        case target
        when TextArea, Field then true
        else                      false
        end
      end

      # A field keeps the keys that move its cursor, and a text area keeps
      # the ones that move between its lines as well.
      def keeps?(key : Key) : Bool
        case target
        when TextArea then AREA_KEPT.includes? key
        when Field    then FIELD_KEPT.includes? key
        else               false
        end
      end

      def press(key : Key) : Nil
        case held = target
        when TextArea then held.press key
        when Field    then held.press key
        end
      end

      # What a field keeps.
      FIELD_KEPT = %w[Home End].map { |name| Key.parse(name).first }

      # What a text area keeps.
      AREA_KEPT = %w[Home End Up Down PageUp PageDown].map { |name| Key.parse(name).first }
    end

    # A row holding `true` or `false`, drawn as a `Checkbox`.
    class ToggleRow < Row
      getter input : Checkbox

      def initialize(key : String, label : String, value : Bool, help : String? = nil)
        super key, label, help
        @input = Checkbox.new "", checked: value
      end

      def value : Value?
        @input.checked?
      end

      def value=(value : Value) : Value
        raise ArgumentError.new "#{key} holds a Bool, not #{value.inspect}" unless value.is_a? Bool

        @input.checked = value
        value
      end

      def heard(event : Event) : Value?
        return unless event.is_a?(Checkbox::Changed) && event.checkbox.same?(@input)

        event.checked?
      end

      def disable_input(off : Bool) : Nil
        @input.disabled = off
      end

      def activate : Nil
        @input.toggle
      end
    end

    # A row holding one of a few strings.
    class ChoiceRow < Row
      getter input : Choice

      def initialize(key : String, label : String, options : Array({String, String}),
                     value : String?, help : String? = nil)
        super key, label, help
        @input = Choice.new options, value
      end

      def value : Value?
        @input.value
      end

      def value=(value : Value) : Value
        raise ArgumentError.new "#{key} holds a String, not #{value.inspect}" unless value.is_a? String

        @input.value = value
        value
      end

      def heard(event : Event) : Value?
        return unless event.is_a?(Choice::Changed) && event.choice.same?(@input)

        event.value
      end

      def disable_input(off : Bool) : Nil
        @input.disabled = off
      end
    end

    # A row holding an integer, held to a range by a `NumberField`.
    class NumberRow < Row
      getter input : NumberField

      def initialize(key : String, label : String, value : Int32, range : Range(Int32, Int32),
                     step : Int32, bar : Bool, help : String? = nil)
        super key, label, help
        @input = NumberField.new value, range, step, bar: bar, up_down: false
      end

      def value : Value?
        @input.value
      end

      def value=(value : Value) : Value
        raise ArgumentError.new "#{key} holds an Int32, not #{value.inspect}" unless value.is_a? Int32

        @input.value = value
        value
      end

      def heard(event : Event) : Value?
        return unless event.is_a?(NumberField::Changed) && event.field.same?(@input)

        event.value
      end

      def disable_input(off : Bool) : Nil
        @input.disabled = off
      end

      def leave : Nil
        @input.settle
      end

      # A number row takes digits and a minus sign.
      def types?(key : Key) : Bool
        Form.printable?(key) && (key.char.ascii_number? || key.char == '-')
      end

      def press(key : Key) : Nil
        @input.press key
      end
    end

    # A row holding free text, typed into a field.
    class TextRow < Row
      # The keys the field keeps, which move its cursor.
      KEPT = {Key.parse("Home").first, Key.parse("End").first}

      getter input : TextInput

      def initialize(key : String, label : String, value : String, help : String? = nil,
                     placeholder : String? = nil)
        super key, label, help
        @input = TextInput.new placeholder: placeholder
        @input.text = value
      end

      def value : Value?
        @input.text
      end

      def value=(value : Value) : Value
        raise ArgumentError.new "#{key} holds a String, not #{value.inspect}" unless value.is_a? String

        @input.text = value
        value
      end

      def heard(event : Event) : Value?
        return unless event.is_a?(TextInput::Edited) && event.field.same?(@input)

        event.text
      end

      def disable_input(off : Bool) : Nil
        @input.disabled = off
      end

      def keeps?(key : Key) : Bool
        KEPT.includes? key
      end

      def typing? : Bool
        true
      end

      def press(key : Key) : Nil
        @input.press key
      end
    end

    # A row that is a thing to do rather than a value to hold. Pressing it
    # makes the form emit `Form::Activated` with the row's key.
    class ActionRow < Row
      getter input : Button

      def initialize(key : String, label : String, hint : String? = nil, help : String? = nil)
        super key, label, help
        @input = Button.new hint || "", padding: Layout::Padding.all(0)
        @input.align = Unicode::Align::Left
        @input.width = Layout::Sizing.grow
      end

      # What the input column says, such as "Enter to open".
      def hint : String
        @input.text
      end

      # :ditto:
      def hint=(text : String) : String
        @input.text = text
      end

      def value : Value?
        nil
      end

      def value=(value : Value) : Value
        raise ArgumentError.new "#{key} is an action and holds no value"
      end

      def heard(event : Event) : Value?
        nil
      end

      # Whether *event* is this row's button being pressed.
      def pressed?(event : Event) : Bool
        event.is_a?(Button::Pressed) && event.button.same?(@input)
      end

      def disable_input(off : Bool) : Nil
        @input.disabled = off
      end

      def activate : Nil
        @input.press
      end
    end
  end
end
