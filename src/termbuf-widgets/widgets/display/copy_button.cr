require "../input/button"
require "./attached"

module TermBuf::Widgets
  # A button that puts something on the clipboard and says it did.
  #
  #     button = CopyButton.new "copy", -> { token }
  #     button.attach app
  #
  # The text is a block rather than a string, so a button beside a field copies
  # whatever the field says now rather than what it said when the button was
  # made. `CopyButton.new "copy", "fixed text"` is the shorthand for one that
  # copies the same thing every time.
  #
  # ### The flash
  #
  # A press swaps the label for `#copied_text` and arms a timer through
  # `App#after` to put it back after `#flash`. A second press while the first
  # is still showing withdraws that timer and arms a fresh one, so holding the
  # key down leaves the label up rather than making it stutter. An application
  # with no clock wired in shows the flash and never takes it down, which is
  # the same bargain a `Toast` makes.
  #
  # ### When there is no clipboard
  #
  # `App#copy` is `nil` on an application whose terminal cannot take a
  # clipboard write, or on one that never wired it up. The button is disabled
  # and says `#unavailable_text` instead, because a control that looks ready
  # and does nothing is worse than one that says it cannot. That is settled at
  # `#attach`, so a button nobody attached is disabled too.
  class CopyButton < Button
    include Copyable

    # How long the flash stays up when nothing says otherwise.
    DEFAULT_FLASH = 1.second

    # Something was copied. Carries the button, since one handler usually
    # answers several.
    struct Copied < Message
      # Which button it was.
      getter button : CopyButton

      # What went on the clipboard.
      getter text : String

      def initialize(@button : CopyButton, @text : String)
      end
    end

    # What is copied, asked afresh at every press.
    property source : Proc(String)

    # What the button says while the flash is up.
    property copied_text : String = "copied"

    # What it says when there is no clipboard to copy to.
    property unavailable_text : String = "no clipboard"

    # How long the flash stays up.
    property flash : Time::Span = DEFAULT_FLASH

    # The timer holding the flash up, or `nil` when none is.
    getter nonce : UInt64? = nil

    @resting_text : String

    def initialize(text : String, @source : Proc(String),
                   copied_text : String = "copied",
                   unavailable_text : String = "no clipboard",
                   flash : Time::Span = DEFAULT_FLASH,
                   padding : Layout::Padding = Layout::Padding.new(0, 1, 0, 1),
                   border : Border? = nil,
                   style : Style? = nil)
      @resting_text = text
      @copied_text = copied_text
      @unavailable_text = unavailable_text
      @flash = flash

      super text, padding: padding, border: border, style: style
      settle
    end

    # :ditto:
    def initialize(text : String, copied : String, **options)
      initialize text, -> { copied }, **options
    end

    # What the button says when it is neither flashing nor unavailable.
    def resting_text : String
      @resting_text
    end

    # Sets it, taking effect at once unless a flash is up.
    def resting_text=(text : String) : String
      @resting_text = text
      settle unless flashing?
      text
    end

    # Whether the flash is up.
    def flashing? : Bool
      !@nonce.nil?
    end

    # Takes the application, and works out whether there is a clipboard behind
    # it.
    def attach(app : App) : Nil
      super
      settle
    end

    # :ditto:
    def detach : Nil
      super
      settle
    end

    # Copies, flashes and says so.
    #
    # `Button#press` emits `Button::Pressed` either way, so a handler watching
    # for that still hears about a press this one could not act on.
    def press : Nil
      return if disabled?

      text = @source.call
      taken = copy text
      super
      return unless taken

      emit Copied.new self, text
      begin_flash
    end

    # Puts the flash up and arms the timer that takes it down.
    private def begin_flash : Nil
      withdraw
      self.text = @copied_text
      @nonce = @app.try &.after(@flash) { @nonce = nil; settle; nil }
    end

    # Withdraws whatever timer is holding a flash up.
    private def withdraw : Nil
      waiting = @nonce
      return unless waiting

      @nonce = nil
      @app.try &.cancel(waiting)
    end

    # Puts the button back to whichever of its two resting states applies.
    private def settle : Nil
      available = copiable?
      self.disabled = !available
      self.text = available ? @resting_text : @unavailable_text
    end
  end
end
