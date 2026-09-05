require "../../message"
require "../input/button_group"
require "../label"
require "./overlay"

module TermBuf::Widgets
  # A box in the middle of the screen that has to be answered before anything
  # else can be.
  #
  #     dialog = Dialog.new "Unsaved changes",
  #       body: Label.new("Save before leaving?"),
  #       actions: %w[Save Discard Cancel]
  #     dialog.open app
  #
  # It is modal by default: a focus scope is pushed with the dialog as its
  # root, so tab moves inside it and a key nothing in it claims stops there
  # rather than reaching the window behind. A `Overlay::Catcher` does the same
  # for the pointer, and a `Overlay::Backdrop` dims what is behind it.
  #
  # Pressing one of the actions takes the dialog down and says `Closed` with
  # which one it was; `Escape` takes it down with `nil`. The application
  # answers the message the way it answers any other:
  #
  #     def handle(event : Event, context : Context) : Nil
  #       return unless event.is_a? Dialog::Closed
  #
  #       save if event.result == 0
  #       context.consume
  #     end
  class Dialog < Overlay
    # The dialog was answered. *result* is which action was pressed, counting
    # from zero, or `nil` for one dismissed without answering.
    struct Closed < Message
      # Which dialog it was, since one handler usually answers several.
      getter dialog : Dialog

      # The action pressed, or `nil` for a dialog that was cancelled.
      getter result : Int32?

      def initialize(@dialog : Dialog, @result : Int32?)
      end
    end

    # The buttons along the bottom.
    getter actions : ButtonGroup

    # What is drawn above them, or `nil` for a dialog that is only a question
    # and its answers.
    getter body : Widget?

    # Which action `#default_key` presses, counting from zero, or `nil` for a
    # dialog with no default.
    property default_action : Int32? = 0

    # The key that presses the default action, or `nil` to leave it alone.
    #
    # It is bound at the dialog rather than at the button, so it fires wherever
    # the keyboard is in the dialog. A binding is answered before any widget's
    # `Widget#handle`, so a dialog holding something that wants `Enter` for
    # itself — a `Field`, a `TextArea` — should be given a different key or
    # none.
    getter default_key : Key?

    # The key that takes the dialog down unanswered, or `nil` for one that
    # cannot be dismissed that way.
    getter cancel_key : Key?

    # The row the actions sit in, which is what aligns them.
    getter action_row : Panel

    def initialize(title : String? = nil,
                   body : Widget? = nil,
                   actions : Enumerable(String) = {"OK"},
                   modal : Bool = true,
                   backdrop : Bool = true,
                   light_dismiss : Bool = false,
                   z : Int32 = Z::DIALOG,
                   width : Layout::Sizing = Layout::Sizing.fit(min: 24),
                   height : Layout::Sizing = Layout::Sizing.fit,
                   actions_align : Layout::Align = Layout::Align::End,
                   border : Border? = nil,
                   style : Style? = nil,
                   default_key : Key? = Key.named(Key::Name::Enter),
                   cancel_key : Key? = Key.named(Key::Name::Escape))
      # Built before the overlay is, because putting a backdrop up is an
      # `Widget#add` and every one of those reaches back through `self`.
      @actions = ButtonGroup.new actions, gap: 1
      @action_row = Panel.new direction: Layout::Direction::Row,
        width: Layout::Sizing.grow, align_x: actions_align
      @action_row.add @actions

      super modal: modal, light_dismiss: light_dismiss, backdrop: backdrop, z: z

      @default_key = default_key
      @cancel_key = cancel_key
      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @gap = 1
      @width = width
      @height = height
      @border = border || Border.rounded(title: title ? " #{title} " : nil)
      @style = style
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      @body = body
      add body if body
      add @action_row

      self.keymap = dialog_keymap
    end

    # The dialog's title, which is the one in its border.
    def title : String?
      @border.try(&.title).try(&.strip)
    end

    # :ditto:
    def title=(title : String?) : String?
      held = @border || Border.rounded
      self.border = held.with_title(title ? " #{title} " : nil)
      title
    end

    # The buttons the dialog offers, in order.
    def buttons : Array(Button)
      @actions.buttons
    end

    # Takes the dialog down, saying *result* was the answer.
    #
    # The message goes out before the dialog is hidden, so it still has a
    # parent to reach.
    def close_with(result : Int32?) : Nil
      return unless open?

      emit Closed.new self, result
      close
    end

    # The keyboard starts on the default action, so `Enter` and `Space` both
    # answer the dialog the way it expects to be answered.
    protected def initial_focus : Widget?
      index = @default_action
      return unless index

      buttons[index]?
    end

    # Presses the default action, if there is one.
    def activate_default : Nil
      index = @default_action
      return unless index

      button = buttons[index]?
      button.try &.press
    end

    # Turns a press of one of the actions into an answer, and a click outside
    # into a dismissal.
    def handle(event : Event, context : Context) : Nil
      if event.is_a? Button::Pressed
        index = buttons.index &.same?(event.button)
        return unless index

        context.consume
        return close_with index
      end

      super
    end

    # The keys the dialog answers wherever the keyboard is inside it.
    private def dialog_keymap : Bindings?
      cancel = @cancel_key
      default = @default_key
      return if cancel.nil? && default.nil?

      map = Bindings.new
      map.bind cancel, "close the dialog", ->(_context : Context) { close_with nil } if cancel
      map.bind default, "press the default action",
        ->(_context : Context) { activate_default } if default
      map
    end

    # A dialog asking a question with two answers, already open on *app*.
    #
    # `Closed#result` is zero for *yes*, one for *no*, and `nil` for a dialog
    # dismissed with `Escape`.
    def self.confirm(app : App, message : String, yes : String = "Yes",
                     no : String = "No", title : String? = nil) : Dialog
      dialog = new title, body: Label.new(message), actions: {yes, no}
      dialog.open app
    end

    # A dialog saying something and offering one way out, already open on
    # *app*.
    def self.alert(app : App, message : String, ok : String = "OK",
                   title : String? = nil) : Dialog
      dialog = new title, body: Label.new(message), actions: {ok}
      dialog.open app
    end
  end
end
