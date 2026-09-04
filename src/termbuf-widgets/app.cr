require "./layout/tree"
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

    # The widget the cursor follows, and the one keys reach first.
    property focused : Widget? = nil

    # Called with every event the tree did not claim. What a program hangs its
    # own quit key or its resize bookkeeping from.
    property on_event : Proc(Event, Nil)? = nil

    def initialize(@screen : Drawing, root : Widget, size : Rect,
                   @events : Channel(Event) = Channel(Event).new(64),
                   policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT)
      @tree = Layout::Tree.new root, size, policy
    end

    # The widget everything else hangs from.
    def root : Widget
      @tree.root
    end

    # Points the app at a different root.
    def root=(root : Widget) : Widget
      @tree.root = root
    end

    # Lays out whatever changed, draws the frame, and answers where the
    # terminal's cursor belongs, or `nil` to hide it.
    def frame : {Int32, Int32}?
      @tree.layout_if_needed
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
      handled = 0

      while event = waiting
        handled += 1
        deliver event
      end

      handled
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

    # What the tree does with one event. `Router` takes this over.
    protected def deliver(event : Event) : Nil
      resize Rect.new(0, 0, event.size.columns, event.size.rows) if event.is_a? Events::Resize

      @on_event.try &.call(event)
    end

    # Where the focused widget wants the cursor, in buffer coordinates.
    private def cursor_for_focus : {Int32, Int32}?
      widget = focused
      return if widget.nil? || widget.hidden?

      spot = widget.cursor_position
      return unless spot

      {widget.rect.x + spot[0], widget.rect.y + spot[1]}
    end
  end
end
