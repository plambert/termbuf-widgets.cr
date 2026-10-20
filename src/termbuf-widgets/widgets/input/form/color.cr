require "../../../widget"
require "../../depth"
require "../../display/color_swatch"
require "../../label"
require "../../overlay/dialog"
require "../../overlay/popover"
require "../../panel"
require "../color_picker"
require "./rows"

module TermBuf::Widgets
  class Form < Widget
    # The input of a `color` row. It is a `ColorSwatch` that takes the
    # keyboard, and `Enter` or `Space` on it calls `#on_press`.
    class SwatchButton < ColorSwatch
      # What the value is written in while the swatch has the keyboard.
      property focused_style : Style = Style::DEFAULT.reverse

      # Whether the swatch refuses the keyboard. It is still drawn, with the
      # value dimmed.
      layout_property? disabled : Bool = false

      # What the value is written in while the swatch is disabled.
      property disabled_style : Style = Style::DEFAULT.faint

      # Called on `Enter` and `Space`.
      property on_press : Proc(Nil)? = nil

      def initialize(color : Color, depth : Depth)
        super color, depth: depth
        self.keymap = Bindings.build do |map|
          map.bind Key.parse("Enter"), "choose a color", ->(_context : Context) { press }
          map.bind Key.parse("Space"), "choose a color", ->(_context : Context) { press }
        end
      end

      # Focus lands here unless the swatch is disabled.
      def focusable? : Bool
        !@disabled
      end

      # Calls `#on_press`, unless the swatch is disabled.
      def press : Nil
        return if @disabled

        @on_press.try &.call
      end

      def value_style : Style
        return @disabled_style if @disabled

        focused? ? @focused_style : super
      end
    end

    # What a `color` row's picker sits in, inside the overlay it opens in.
    #
    # The overlay is modal, so the picker's messages stop at it and never
    # reach the form. The box hears them first and hands each color to the
    # row. It also binds `Escape`, which puts the row's color back.
    class PickerBox < Panel
      # What the line under the picker says.
      HINT = "Enter takes the color. Escape puts it back."

      # The line under the picker.
      getter hint : Label

      def initialize(@row : ColorRow)
        super direction: Layout::Direction::Column
        @hint = Label.new HINT, wrap: Layout::Wrap::Words
        @hint.width = Layout::Sizing.grow
        self.keymap = Bindings.build do |map|
          map.bind Key.parse("Escape"), "put the color back",
            ->(_context : Context) { @row.cancel }
        end
      end

      # Takes *picker* from wherever it was and puts it above the hint.
      def hold(picker : ColorPicker) : Nil
        return if picker.parent.same?(self)

        picker.parent.try &.remove(picker)
        clear
        add picker, @hint
      end

      # Hands each change the picker makes to the row, unless `Escape` closed
      # the picker before the change arrived.
      def handle(event : Event, context : Context) : Nil
        return unless event.is_a? ColorPicker::Changed

        context.consume
        @row.picked event.color unless @row.cancelled?
      end
    end

    # A row holding a color, drawn as a swatch.
    #
    # `Enter`, `Space` and a click open a `ColorPicker` in a `Popover` hanging
    # off the swatch. When the popover would cover the row, because there is
    # room neither under it nor over it, the picker opens in a `Dialog`
    # instead. Each change in the picker sets the row's value at once and
    # emits `Form::Changed`.
    #
    # `Enter` closes the picker and keeps the color. On the grid it takes the
    # color under the cursor first, and in a field it takes what was typed.
    # A click outside a popover, or the dialog's button, closes it the same
    # way. `Escape` closes it and puts back the color the row held when it
    # opened, with a `Form::Changed` when that differs from the color held
    # now. The picker's own `Tab` wraps inside it, so these are the ways out.
    #
    # The picker opens over the screen, so the form has to be given the
    # application with `Form#attach` first. Until then the row does nothing
    # when pressed.
    class ColorRow < Row
      # The button the dialog closes with.
      DONE = "Done"

      getter input : SwatchButton

      # The color the row held when the picker opened.
      getter before : Color

      # The popover the picker opens in, once it has been opened in one.
      getter popover : Popover? = nil

      # The dialog it opens in when the popover does not fit, once it has.
      getter dialog : Dialog? = nil

      @value : Color
      @depth : Depth?
      @picker : ColorPicker? = nil
      @popover_box : PickerBox? = nil
      @dialog_box : PickerBox? = nil

      def initialize(key : String, label : String, value : Color, depth : Depth? = nil,
                     help : String? = nil)
        super key, label, help
        @value = value
        @before = value
        @depth = depth
        @input = SwatchButton.new value, depth || Depth::TrueColor
        @input.on_press = -> { open }
      end

      # How many colors the picker offers. The row's own depth when it was
      # given one, and the form's `Form#depth` otherwise.
      def depth : Depth
        @depth || @owner.try(&.depth) || Depth::TrueColor
      end

      # Gives the row a depth of its own, or `nil` to take the form's.
      def depth=(depth : Depth?) : Depth?
        @depth = depth
        refresh_depth
        depth
      end

      # Hands `#depth` to the swatch and the picker.
      def refresh_depth : Nil
        shown = depth
        @input.depth = shown
        @picker.try &.depth=(shown)
      end

      # :nodoc:
      def join(form : Form) : Nil
        super
        refresh_depth
      end

      def value : Value?
        @value
      end

      def value=(value : Value) : Value
        raise ArgumentError.new "#{key} holds a Color, not #{value.inspect}" unless value.is_a? Color

        @value = value
        @input.color = value
        @picker.try &.value=(value) if open?
        value
      end

      # The picker's changes reach the row through its `PickerBox`.
      def heard(event : Event) : Value?
        nil
      end

      # `#rrggbb`, or "default" for the terminal's own color.
      def text : String?
        @value.default? ? "default" : Depth.hex(depth.shown(@value))
      end

      def disable_input(off : Bool) : Nil
        @input.disabled = off
      end

      def activate : Nil
        open
      end

      # The picker, made the first time it is asked for.
      def picker : ColorPicker
        @picker ||= build_picker
      end

      # Whether the picker is up, in either overlay.
      def open? : Bool
        @popover.try(&.open?) || @dialog.try(&.open?) || false
      end

      # Whether `Escape` closed the picker last time. Changes the picker sends
      # after that are dropped.
      getter? cancelled : Bool = false

      # Whether *dialog* is the one this row opens.
      def owns?(dialog : Dialog) : Bool
        @dialog.try(&.same?(dialog)) || false
      end

      # Opens the picker on the row's color, in a popover where it fits and a
      # dialog where it does not.
      #
      # The popover is laid out where it would land, by the same flip and
      # clamp rules as any float. A popover that fits neither under the row
      # nor over it is clamped onto the row, and that is when the dialog is
      # used instead.
      def open : Nil
        form = @owner
        app = form.try &.app
        return unless form && app && @enabled
        return if open?

        held = picker
        held.value = @value
        @before = @value
        @cancelled = false

        popover = @popover || build_popover(form)
        (@popover_box ||= PickerBox.new(self)).hold held
        popover.open app
        app.tree.layout
        return if clear_of_row? popover.rect

        popover.close
        dialog = @dialog || build_dialog(form)
        dialog_box.hold held
        dialog.open app
      end

      # Closes the picker and keeps the color.
      def close : Nil
        @popover.try &.close
        @dialog.try &.close
      end

      # Closes the picker and puts back the color the row held when it opened.
      def cancel : Nil
        @cancelled = true
        close
        picked @before
      end

      # Takes *color* from the picker and says so, unless the row holds it
      # already.
      def picked(color : Color) : Nil
        return if color == @value

        @value = color
        @input.color = color
        form = @owner
        form.emit Changed.new(form, key, color) if form
      end

      private def clear_of_row?(placed : Rect) : Bool
        row = @input.rect
        placed.y >= row.y + row.height || placed.y + placed.height <= row.y
      end

      # A picker whose `Enter` closes it, wherever the keyboard is in it.
      private def build_picker : ColorPicker
        made = ColorPicker.new @value, depth: depth
        on_enter made.grid, "take this color and close" do
          made.grid.take
          picked made.value
        end
        on_enter made.hex, "take this color and close" do
          made.settle
          picked made.value
        end
        {made.red, made.green, made.blue}.each do |field|
          on_enter(field, "take this level and close") { field.commit }
        end
        made
      end

      # Binds `Enter` on *widget* to the block and then to closing the picker.
      private def on_enter(widget : Widget, description : String, &action : -> Nil) : Nil
        closing = Bindings.build do |map|
          map.bind Key.parse("Enter"), description,
            ->(_context : Context) { action.call; close }
        end
        widget.keymap = (widget.keymap || Bindings.new).merge closing
      end

      # Held to the screen, so that a picker with too little room shrinks
      # and leaves its grid out.
      private def on_screen(sizing : Layout::Sizing) : Layout::Sizing
        sizing.with_max_percent 100, of: Layout::Sizing::Basis::Screen
      end

      private def build_popover(form : Form) : Popover
        box = @popover_box ||= PickerBox.new(self)
        made = Popover.new @input, content: box, modal: true, cancel_key: nil,
          width: on_screen(Layout::Sizing.fit), height: on_screen(Layout::Sizing.fit)
        form.add made
        @popover = made
      end

      private def dialog_box : PickerBox
        @dialog_box ||= PickerBox.new(self)
      end

      private def build_dialog(form : Form) : Dialog
        made = Dialog.new label, body: dialog_box, actions: {DONE},
          default_key: nil, cancel_key: nil,
          width: on_screen(Layout::Sizing.fit(min: 24)), height: on_screen(Layout::Sizing.fit)
        made.default_action = nil
        form.add made
        @dialog = made
      end
    end
  end
end
