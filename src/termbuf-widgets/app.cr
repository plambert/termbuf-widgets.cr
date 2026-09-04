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

    # Called with every event the tree did not claim. What a program hangs its
    # own quit key or its resize bookkeeping from.
    property on_event : Proc(Event, Nil)? = nil

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

    # The widget everything else hangs from.
    def root : Widget
      @tree.root
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

      Renderer.render @tree, @screen
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
      return if @router.dispatch event

      @on_event.try &.call(event)
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
