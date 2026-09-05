require "./focus"
require "./layout/tree"
require "./router"
require "./renderer"
require "./widget"

module TermBuf::Widgets
  # A widget tree, the surface it is drawn on, and the events it answers.
  #
  # An app is given a `TermBuf::Drawing` and a channel rather than a
  # `TermBuf::Terminal`, so the thing that owns the device stays outside it: a
  # spec drives one over a `TermBuf::Buffer` with nothing to open or tear down,
  # and a program hands it the terminal's own surface and event channel.
  #
  # Two calls make a loop. `#pump` takes everything waiting and lets the tree
  # answer it; `#frame` lays out what changed, draws it, and says where the
  # cursor goes. Handlers run only inside `#pump` and only set properties, so
  # every hit test in a frame runs against the rectangles that are on the
  # screen rather than against ones a handler moved halfway through.
  class App
    # Where frames are drawn.
    getter screen : Drawing

    # The widget tree and the screen it is laid out against.
    getter tree : Layout::Tree

    # Everything the terminal has to say, and anything else sent down the same
    # channel.
    getter events : Channel(Event)

    # Where the last `#frame` left the terminal's cursor, or `nil` for a frame
    # that wants it hidden.
    getter cursor : {Int32, Int32}? = nil

    # Which widget has the keyboard, and what tab moves it between.
    getter focus : Focus::Stack

    # Where events go once they are off the channel.
    getter router : Router

    # The keys the application answers after every widget in the chain has
    # declined them. Tab and Shift+Tab live here rather than being wired into
    # the router, so a program that wants different keys for them rebinds
    # rather than patches.
    getter keymap : Bindings

    # How the application arms a timer, or `nil` for one with no clock.
    #
    # `TermBuf::Terminal#after` is what a program hands over; a spec hands over
    # a counter and pushes the `TermBuf::Events::Timer` itself. Nothing in the
    # widget layer opens a device, so the clock arrives the same way the screen
    # and the event channel do: from whatever owns the terminal.
    property after : Proc(Time::Span, UInt64)? = nil

    # How it withdraws one. `TermBuf::Terminal#cancel`.
    property cancel : Proc(UInt64, Nil)? = nil

    # What to run when each armed timer goes off, by the nonce naming it.
    @timers = {} of UInt64 => Proc(Nil)

    # How the application puts text on the system clipboard, or `nil` for one
    # with no clipboard behind it.
    #
    # `TermBuf::Terminal#clipboard` is what a program hands over, the same way
    # it hands over the clock:
    #
    #     app.copy = ->(text : String) { terminal.clipboard.copy text }
    #
    # Nothing in the widget layer opens a device, and a clipboard is one. Left
    # `nil`, a widget that wanted to copy says so — a `CopyButton` draws itself
    # unavailable rather than pretending — and nothing is written.
    property copy : Proc(String, Nil)? = nil

    # Called with every event the tree did not claim. What a program hangs its
    # own quit key or its resize bookkeeping from.
    property on_event : Proc(Event, Nil)? = nil

    # Where a widget's pictures go, or `nil` for an application that has none.
    # `TermBuf::Terminal#images` is one.
    property images : ImageStore? = nil

    def initialize(@screen : Drawing, root : Widget, size : Rect,
                   @events : Channel(Event) = Channel(Event).new(64),
                   policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT,
                   keymap : Bindings? = nil)
      @tree = Layout::Tree.new root, size, policy
      @keymap = keymap || App.default_keymap
      @focus = Focus::Stack.new root, @keymap
      @router = Router.new @tree, @focus
    end

    # Moving the keyboard from one widget to the next and back, which every
    # application wants and none should have to write.
    def self.default_keymap : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Tab"), "focus the next widget",
          ->(context : Context) { context.focus.next; nil }
        map.bind Key.parse("Shift+Tab"), "focus the previous widget",
          ->(context : Context) { context.focus.previous; nil }
      end
    end

    # Puts a different keymap under the whole application, which is the one
    # the base focus scope answers with after every widget has declined a key.
    #
    # `Keymap#merge` is how a binding is added without losing the ones that are
    # there: `app.keymap = app.keymap.merge other`.
    def keymap=(bindings : Bindings) : Bindings
      @keymap = bindings
      @focus.scopes.first.keymap = bindings
      bindings
    end

    # The widget everything else hangs from.
    def root : Widget
      @tree.root
    end

    # Arms a timer for *span* from now and answers the nonce naming it, or
    # `nil` for an application with no clock.
    #
    # The block runs once, when the `TermBuf::Events::Timer` reaches `#pump`,
    # and the registration is dropped whether or not anything is listening. A
    # timer nobody armed — one belonging to the program rather than to a widget
    # — is left alone and delivered into the tree like any other event.
    def after(span : Time::Span, &block : ->) : UInt64?
      arm = @after
      return unless arm

      nonce = arm.call span
      @timers[nonce] = block
      nonce
    end

    # Withdraws the timer *nonce* names, if it is one of ours.
    def cancel(nonce : UInt64) : Nil
      return unless @timers.delete nonce

      @cancel.try &.call(nonce)
    end

    # The widget with the keyboard.
    def focused : Widget?
      @focus.current
    end

    # Lays out whatever changed, draws the frame, and answers where the
    # terminal's cursor belongs, or `nil` to hide it.
    def frame : {Int32, Int32}?
      # The flag that says the tree has to be laid out again is the same flag
      # that says the tab order is stale: adding a widget, taking one out and
      # hiding one are all invalidations.
      stale = @tree.dirty?
      @tree.layout_if_needed
      @focus.rebuild if stale

      Renderer.render @tree, @screen, @images
      @cursor = cursor_for_focus
    end

    # :ditto:
    #
    # Yields the cursor to whatever is driving the terminal, which is what
    # paints the frame the drawing left behind.
    def frame(& : {Int32, Int32}? -> Nil) : Nil
      yield frame
    end

    # Lays the screen out again at *size*.
    def resize(size : Rect) : Nil
      @tree.screen = size
    end

    # Takes everything waiting on the channel, without blocking, and answers
    # how many events that was.
    def pump : Int32
      handled = @router.drain

      while event = waiting
        handled += 1
        deliver event
      end

      handled
    end

    # Waits for something to happen, answers it, and takes anything else that
    # came with it. Answers `false` when the channel has closed and there is
    # nothing more coming, which is what ends a loop.
    #
    #     while app.wait
    #       app.frame { |spot| terminal.cursor.move_to *spot if spot }
    #       terminal.paint
    #     end
    def wait : Bool
      event = @events.receive?
      return false unless event

      deliver event
      pump
      true
    end

    # One event, or `nil` when nothing is waiting and nothing is closed.
    private def waiting : Event?
      select
      when event = @events.receive?
        event
      else
        nil
      end
    end

    # What the tree does with one event, and what happens to one it declined.
    protected def deliver(event : Event) : Nil
      resize Rect.new(0, 0, event.size.columns, event.size.rows) if event.is_a? Events::Resize
      return if fired? event
      return if @router.dispatch event

      @on_event.try &.call(event)
    end

    # Whether *event* is a timer this application armed, in which case whatever
    # armed it has now been run and the event goes no further.
    private def fired?(event : Event) : Bool
      return false unless event.is_a? Events::Timer

      waiting = @timers.delete event.nonce
      return false unless waiting

      waiting.call
      true
    end

    # Where the focused widget wants the cursor, in buffer coordinates.
    #
    # A widget answers in its own content box, which is the box it is drawn
    # through, so a border around it moves the cursor with everything else it
    # holds.
    private def cursor_for_focus : {Int32, Int32}?
      widget = focused
      return if widget.nil? || widget.hidden?

      spot = widget.cursor_position
      return unless spot

      content = widget.content
      {content.x + spot[0], content.y + spot[1]}
    end
  end
end
