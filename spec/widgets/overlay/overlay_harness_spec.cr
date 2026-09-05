# Fixtures the overlay specs share.
#
# The name carries the `_spec` suffix because everything under `spec/` that
# does not is a linter warning, and the directories the runner treats as
# support live elsewhere. There are no examples in here.
require "../input/input_harness_spec"

module Fixtures
  # A screen with one focusable widget filling it, and a log at the root that
  # writes down every message anything had to say.
  #
  # What every overlay spec wants underneath the overlay: something the
  # keyboard could be on, something a click could land on, and somewhere for
  # the overlay's own messages to arrive.
  class Ground
    # The root, which hears every message.
    getter root : MessageLog

    # The widget filling the screen under the overlay.
    getter under : Box

    # The application drawing it.
    getter app : TestApp

    def initialize(columns : Int32 = 40, rows : Int32 = 12)
      @root = MessageLog.new width: TermBuf::Widgets::Layout::Sizing.grow,
        height: TermBuf::Widgets::Layout::Sizing.grow
      @under = Box.new
      @under.focusable = true
      @under.width = TermBuf::Widgets::Layout::Sizing.grow
      @under.height = TermBuf::Widgets::Layout::Sizing.grow
      @under.mark = "."
      @root.add @under

      @app = TestApp.new @root, columns, rows
      @app.frame
    end

    # Draws a frame and answers what the screen shows.
    def lines : Array(String)
      @app.frame
      @app.lines
    end

    # Draws a frame and answers the buffer, for a spec asking about styles.
    def painted : TermBuf::Buffer
      @app.frame
      @app.buffer
    end

    # The style one cell of the painted screen carries.
    def style_at(x : Int32, y : Int32) : TermBuf::Style
      buffer = painted
      buffer.styles[buffer.back[x, y].style]
    end

    # The messages of one kind that reached the root, once everything waiting
    # has been delivered.
    #
    # A message is posted rather than dispatched, so anything emitted outside
    # an event — by an overlay a spec opened or closed itself — is still in the
    # router's queue until something pumps.
    def of(kind : Klass.class) : Array(Klass) forall Klass
      Fixtures.settle @app
      @root.of kind
    end

    # Sends *keys* and lets everything they caused be delivered.
    #
    # A frame is taken first and last, the way a real loop takes one: an event
    # is answered against the rectangles that are on the screen rather than
    # against ones a handler moved since.
    def press(keys : String) : Nil
      @app.frame
      Fixtures.presses @app, keys
      @app.frame
    end

    # Clicks at (*x*, *y*).
    def click(x : Int32, y : Int32) : Nil
      @app.frame
      Fixtures.click @app, x, y
      @app.frame
    end

    # Presses the pointer at (*x*, *y*) without letting go, which is the half
    # of a click that dismisses an overlay.
    def press_at(x : Int32, y : Int32) : Nil
      @app.frame
      Fixtures.mouse @app, TermBuf::Input::Mouse::Action::Press, x, y
      @app.frame
    end

    # Moves the pointer to (*x*, *y*) with nothing held down.
    def move_to(x : Int32, y : Int32) : Nil
      @app.frame
      Fixtures.mouse @app, TermBuf::Input::Mouse::Action::Motion, x, y,
        TermBuf::Input::Mouse::Button::None
      @app.frame
    end

    # A timer that hands out nonces in order and remembers the spans it was
    # given, so a spec can fire one without waiting for it.
    class Clock
      # Every span armed, in order, by the nonce naming it.
      getter armed = {} of UInt64 => Time::Span

      # Every nonce withdrawn.
      getter cancelled = [] of UInt64

      @next : UInt64 = 1

      # Wires this clock into *app*, in place of the terminal's own.
      def install(app : TestApp) : Nil
        app.after = ->(span : Time::Span) { arm span }
        app.cancel = ->(nonce : UInt64) { withdraw nonce }
      end

      # Arms a timer and answers the nonce naming it.
      def arm(span : Time::Span) : UInt64
        nonce = @next
        @next += 1
        @armed[nonce] = span
        nonce
      end

      # Withdraws one.
      def withdraw(nonce : UInt64) : Nil
        @armed.delete nonce
        @cancelled << nonce
      end

      # The nonces still waiting, oldest first.
      def waiting : Array(UInt64)
        @armed.keys.sort!
      end

      # Fires the timer *nonce* names on *app*, the way the terminal would.
      def fire(app : TestApp, nonce : UInt64) : Nil
        @armed.delete nonce
        app.events.send TermBuf::Events::Timer.new(nonce)
        Fixtures.settle app
        app.frame
      end
    end
  end
end
