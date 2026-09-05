require "../../app"
require "../../message"
require "../label"
require "../panel"
require "./overlay"

module TermBuf::Widgets
  # A short message in a corner of the screen, which goes away on its own.
  #
  # Made by a `Toasts`, never on its own: what a toast is depends on where the
  # stack it belongs to puts it and on the clock that takes it down again.
  class Toast < Panel
    # The toast went away, whether it was clicked, timed out or pushed off the
    # end of the stack.
    struct Dismissed < Message
      # Which toast it was.
      getter toast : Toast

      def initialize(@toast : Toast)
      end
    end

    # What it says.
    getter label : Label

    # The stack it belongs to.
    getter toasts : Toasts

    # How long it stays up, or `nil` for one that stays until it is dismissed.
    getter ttl : Time::Span?

    # The timer armed for it, or `nil` for one with no clock behind it.
    property nonce : UInt64? = nil

    def initialize(@toasts : Toasts, text : String, @ttl : Time::Span? = nil,
                   style : Style? = nil, border : Border? = nil)
      @label = Label.new text, wrap: Layout::Wrap::None

      super direction: Layout::Direction::Row,
        padding: Layout::Padding.new(0, 1, 0, 1),
        border: border, style: style
      add @label
    end

    # What the toast says.
    def text : String
      @label.text
    end

    # :ditto:
    def text=(text : String) : String
      @label.text = text
    end

    # A click anywhere on the toast takes it down, which is the one thing a
    # toast has to answer.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse
      return if event.button.wheel? || !event.action.press?
      return unless frame.contains? event.x, event.y

      context.consume
      @toasts.dismiss self
    end
  end

  # The stack of toasts in one corner of the screen.
  #
  #     toasts = Toasts.new app
  #     toasts.show "saved"
  #     toasts.show "and again", ttl: 2.seconds
  #
  # The newest toast is always the one nearest the corner: a stack in a bottom
  # corner grows upward and one in a top corner grows downward, so the thing
  # that just happened is in the same place either time. Past `#max_visible`
  # the oldest is pushed off.
  #
  # Timed dismissal wants a clock, which the widget layer does not have: an
  # application wires `App#after` and `App#cancel` to its terminal's, and until
  # it does a toast stays up until it is clicked or dismissed. See `App#after`.
  #
  #     app.after = ->(span : Time::Span) { terminal.after span }
  #     app.cancel = ->(nonce : UInt64) { terminal.cancel nonce }
  class Toasts
    # How long a toast stays up when nothing says otherwise.
    DEFAULT_TTL = 5.seconds

    # The float the toasts sit in.
    getter container : Panel

    # The application they are shown on.
    getter app : App

    # The toasts that are up, oldest first.
    getter toasts = [] of Toast

    # How many are shown at once. Making a toast past this pushes the oldest
    # off the end.
    property max_visible : Int32

    # Which corner the stack sits in.
    getter corner : Layout::AttachPoint

    def initialize(@app : App,
                   corner : Layout::AttachPoint = Layout::AttachPoint::RightBottom,
                   z : Int32 = Overlay::Z::TOAST,
                   @max_visible : Int32 = 3,
                   gap : Int32 = 0,
                   margin : Layout::Padding = Layout::Padding.all(1))
      @corner = corner
      @container = Panel.new direction: Layout::Direction::Column, gap: gap,
        margin: margin
      @container.floating = Layout::Floating.on nil, corner, corner, z: z
      @app.root.add @container
    end

    # Whether the newest toast goes at the top of the stack rather than the
    # bottom of it, which is what puts it nearest the corner either way.
    def newest_first? : Bool
      !(@corner.left_bottom? || @corner.center_bottom? || @corner.right_bottom?)
    end

    # Puts *text* up and answers the toast it made.
    #
    # *ttl* is how long it stays; `nil` keeps it up until it is clicked or
    # dismissed. A toast made where nothing wired a clock into the application
    # stays up the same way, since there is nothing to take it down.
    def show(text : String, style : Style? = nil, ttl : Time::Span? = DEFAULT_TTL,
             border : Border? = nil) : Toast
      toast = Toast.new self, text, ttl, style, border
      @toasts << toast
      evict
      restack
      arm toast

      toast
    end

    # Takes *toast* down, saying so, and answers whether it was up.
    def dismiss(toast : Toast) : Bool
      return false unless @toasts.includes? toast

      disarm toast
      @toasts.delete toast
      restack
      announce toast

      true
    end

    # Takes every toast down without saying anything about any of them, which
    # is what an application tearing its screen down wants.
    def clear : Nil
      @toasts.each { |toast| disarm toast }
      @toasts.clear
      restack
    end

    # Arms the timer that takes *toast* down.
    private def arm(toast : Toast) : Nil
      span = toast.ttl
      return unless span

      toast.nonce = @app.after(span) { dismiss toast; nil }
    end

    # Withdraws it, for a toast going down early.
    private def disarm(toast : Toast) : Nil
      nonce = toast.nonce
      return unless nonce

      toast.nonce = nil
      @app.cancel nonce
    end

    # Pushes the oldest off the end until the stack is short enough.
    private def evict : Nil
      while @toasts.size > @max_visible
        oldest = @toasts.shift
        disarm oldest
        announce oldest
      end
    end

    # Says *toast* has gone.
    #
    # Sent from the container rather than from the toast, because a message is
    # delivered on the next pump and starts at the emitter's parent: a toast
    # that has already been taken out of the stack has none, and nothing would
    # hear it.
    private def announce(toast : Toast) : Nil
      @container.emit Toast::Dismissed.new toast
    end

    # Puts the toasts in the container in the order the corner asks for.
    private def restack : Nil
      @container.clear
      shown = newest_first? ? @toasts.reverse : @toasts
      shown.each { |toast| @container.add toast }
    end
  end
end
