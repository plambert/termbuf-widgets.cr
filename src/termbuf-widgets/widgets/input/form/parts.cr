require "../../../message"
require "../../../router"
require "../../../widget"
require "../../field"
require "../../panel"
require "../../scrollable"
require "../../scrollbar"
require "../interactive"

module TermBuf::Widgets
  class Form < Widget
    # The field behind a `text` row. It is a `Field` that can be disabled and
    # that says when its text changes.
    class TextInput < Field
      # The text changed under the keyboard or a paste.
      struct Edited < Message
        # Which field it was.
        getter field : TextInput

        # What it now holds.
        getter text : String

        def initialize(@field : TextInput, @text : String)
        end
      end

      # Whether the field refuses the keyboard. It is still drawn, dimmed.
      layout_property? disabled : Bool = false

      # What the field is drawn in while it is disabled.
      property disabled_style : Style = Style::DEFAULT.faint

      # Focus lands here unless the field is disabled.
      def focusable? : Bool
        !@disabled
      end

      # Does what *key* means to the editor. An accepted line stays in the
      # field, since the form still holds it.
      def press(key : Key) : Nil
        return if @disabled

        before = text
        outcome = @editor.handle key
        @editor.text = @editor.accepted if outcome.accepted?
        emit Edited.new(self, text) unless text == before
        announce outcome
      end

      # Takes the paste as text and says so.
      def paste(text : String) : Nil
        return if @disabled

        before = self.text
        super
        emit Edited.new(self, self.text) unless self.text == before
      end

      def style : Style?
        base = @style || Style::DEFAULT
        @disabled ? base.merge(@disabled_style) : base
      end
    end

    # The label and the input of one row, side by side or one above the other.
    #
    # Which way it runs is asked of the form at every layout, so a form that
    # is resized narrower than `Form#narrow` puts its labels above.
    class Pair < Panel
      include Interactive

      # The row this pair draws.
      getter row : Row

      def initialize(@form : Form, @row : Row)
        super width: Layout::Sizing.grow
      end

      def direction : Layout::Direction
        @form.labels_above? ? Layout::Direction::Column : Layout::Direction::Row
      end

      def gap : Int32
        @form.labels_above? ? 0 : 1
      end

      # The narrowest the pair can be is the narrowest it is with the label
      # above, whichever way it runs now.
      #
      # The widths are measured before the form knows its own, so a pair that
      # runs across at that point would otherwise insist on the label and the
      # input side by side, and push a narrow form wider than its parent.
      #
      # :nodoc:
      def min_size=(min_size : {Int32, Int32}) : {Int32, Int32}
        stacked = (visible_children.max_of?(&.min_width) || 0) + inset.horizontal
        super({Math.min(min_size[0], stacked), min_size[1]})
      end

      # A click on the label, or beside the input, presses the row.
      def handle(event : Event, context : Context) : Nil
        return unless event.is_a? Events::Mouse
        return context.consume if !@row.enabled? && frame.contains?(event.x, event.y)

        clicked event, context do
          @form.click @row, context
        end
      end
    end

    # The label of a row, as wide as the label column. A label above its input
    # in a form narrower than that is cut at the edge rather than widening
    # the form.
    class Caption < Label
      def initialize(text : String)
        super text, wrap: Layout::Wrap::None
      end

      # :nodoc:
      def min_size=(min_size : {Int32, Int32}) : {Int32, Int32}
        super({0, min_size[1]})
      end
    end

    # The column the rows scroll in.
    #
    # It may be laid out as short as the first section header and its first
    # row, however tall the rows are, so a form with no room left scrolls
    # rather than pushing what is under it off the screen.
    class Window < Scrollable
      def initialize
        super height: Layout::Sizing.fit
        self.keymap = nil
      end

      # The rows take the keyboard. The window never does.
      def focusable? : Bool
        false
      end

      # :nodoc:
      def min_size=(min_size : {Int32, Int32}) : {Int32, Int32}
        super({min_size[0], Math.min(min_size[1], floor)})
      end

      # Rows down to the end of the first row, which is as short as the window
      # is allowed to be.
      def floor : Int32
        rows = 0
        visible_children.each do |child|
          rows += child.rect.height
          return rows if child.is_a? Pair
        end

        rows
      end

      # Where *widget* starts, in rows from the top of the content, or `nil`
      # for one that is not in the window.
      def top_of(widget : Widget) : Int32?
        offset_of(widget).try &.[1]
      end

      # Moves the window as little as it takes to show *widget* with *margin*
      # rows of what is around it.
      def bring(widget : Widget, margin : Scrolls::Margin) : Nil
        top = top_of widget
        return unless top

        keep = margin.rows_for viewport_size[1]
        reveal 0, top - keep, 1, widget.rect.height + keep * 2
      end
    end

    # A scrollbar that draws only while the rows are taller than the window.
    # It keeps its column either way, so the rows do not move sideways when
    # it appears.
    class Bar < Scrollbar
      def draw(view : View) : Nil
        held = target
        return unless held && held.content_size[1] > held.viewport_size[1]

        super
      end
    end

    # The line under the window that shows the help of the focused row, and
    # its note on the line after.
    class HelpLine < Widget
      # The form whose rows it describes.
      property form : Form? = nil

      def initialize
        @width = Layout::Sizing.grow
        @height = Layout::Sizing.fixed 1
      end

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        Layout::Intrinsic.new 0, 0
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        1
      end

      def draw(view : View) : Nil
        return if view.width <= 0 || view.height <= 0

        owner = @form
        row = owner.try &.focused_row
        return unless owner && row

        if help = row.help
          view.write 0, 0, Unicode.truncate(help, view.width, view.policy), owner.help_style
        end

        note = row.note
        return unless note && view.height > 1

        view.write 0, 1, Unicode.truncate(note, view.width, view.policy), owner.note_style
      end
    end
  end
end
