require "../widget"
require "./rows"
require "./scrolls"

module TermBuf::Widgets
  # A window over rows, which draws the ones that are showing and no others.
  #
  #     list = VirtualList.new Rows.of(names)
  #     list.on_draw = ->(view : View, index : Int32, name : String,
  #                       chosen : Bool, focused : Bool) do
  #       lit = chosen && focused
  #       view.write 0, 0, name, lit ? Style::DEFAULT.reverse : Style::DEFAULT
  #     end
  #
  # The block is told which row is chosen and, separately, whether the list has
  # the keyboard, because those are two different things to draw. A list that
  # has lost focus still knows where its selection is, and a highlight left lit
  # says the arrows will move it when they will not.
  #
  # What makes it virtual is that it holds no widget per row. It asks its
  # `Rows` how many there are, and then asks for the rows in the window and
  # nothing else, so twenty rows of a hundred thousand cost what twenty rows of
  # twenty do.
  #
  # It is a `Scrolls`, so a `Scrollbar` attaches to it the same way one
  # attaches to a `Scrollable`. It scrolls itself rather than sitting inside a
  # scroll panel, because a panel would have to be as tall as every row for
  # the clipping to have anything to clip.
  #
  # Scrolling and moving the selection change nothing about any rectangle, so
  # neither costs a layout: the next frame draws different rows in the same
  # box.
  class VirtualList(T) < Widget
    include Scrolls

    # Where the rows come from.
    property rows : Rows(T)

    # Which row is chosen, from zero.
    getter selected : Int32 = 0

    # The first row showing.
    getter scroll : Int32 = 0

    # How many cells one notch of the wheel moves.
    property wheel : Int32 = 3

    # What draws one row, or `nil` for the default, which writes what the row
    # answers to `#to_s` and reverses it when it is the chosen one.
    #
    # Called with the view, the row's index, the row, whether it is the chosen
    # one and whether the list is focused. The view is cut to that row: one
    # cell tall, as wide as the list.
    property on_draw : Proc(View, Int32, T, Bool, Bool, Nil)? = nil

    # The height the selection was last brought into view at, so that a window
    # which changed size can bring it back without fighting a scroll somebody
    # asked for.
    @revealed_at : Int32 = -1

    def initialize(@rows : Rows(T),
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow(min: 1),
                   selected : Int32 = 0,
                   style : Style? = nil)
      @width = width
      @height = height
      @selected = selected
      @style = style
      @keymap = VirtualList.moves self
    end

    # The keys that move the selection. A list is given its own copy, so
    # rebinding one leaves the rest alone.
    def self.moves(list : VirtualList(T)) : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Up"), "the row before", ->(_context : Context) { list.select list.selected - 1 }
        map.bind Key.parse("Down"), "the row after", ->(_context : Context) { list.select list.selected + 1 }
        map.bind Key.parse("PageUp"), "a window back", ->(_context : Context) { list.select list.selected - list.page }
        map.bind Key.parse("PageDown"), "a window on", ->(_context : Context) { list.select list.selected + list.page }
        map.bind Key.parse("Home"), "the first row", ->(_context : Context) { list.select 0 }
        map.bind Key.parse("End"), "the last row", ->(_context : Context) { list.select list.rows.size - 1 }
      end
    end

    # Focus lands here: it is the widget the arrow keys are for.
    def focusable? : Bool
      true
    end

    # A list is a window down, never across.
    def clip_x? : Bool
      false
    end

    # :ditto:
    def clip_y? : Bool
      true
    end

    # Rows there are, and cells across.
    def content_size : {Int32, Int32}
      {content.width, @rows.size}
    end

    # Rows that fit.
    def viewport_size : {Int32, Int32}
      box = content
      {box.width, box.height}
    end

    # How many rows a page key moves, which is a window's worth.
    def page : Int32
      Math.max viewport_size[1], 1
    end

    # Always nothing: a list does not scroll sideways.
    def scroll_x : Int32
      0
    end

    # The first row showing, which is the same number of cells down.
    def scroll_y : Int32
      @scroll
    end

    # The rows that are showing.
    def visible_range : Range(Int32, Int32)
      room = viewport_size[1]
      return (0...0) if room <= 0 || @rows.empty?

      first = @scroll.clamp 0, Math.max(@rows.size - 1, 0)
      (first...Math.min(first + room, @rows.size))
    end

    # Yields the index and the row of everything showing, top first.
    def each_visible(& : Int32, T ->) : Nil
      visible_range.each { |index| yield index, @rows.row(index) }
    end

    # Moves the window, stopping at either end.
    def scroll_by(dx : Int32, dy : Int32) : Nil
      scroll_to_row @scroll + dy
    end

    # :ditto:
    def scroll_by(*, dx : Int32 = 0, dy : Int32 = 0) : Nil
      scroll_by dx, dy
    end

    # Puts row *index* at the top of the window, as near as the ends allow.
    def scroll_to_row(index : Int32) : Nil
      @scroll = index.clamp 0, max_scroll[1]
    end

    # Moves the window as little as it takes to show row *index*.
    def scroll_to(index : Int32) : Nil
      room = viewport_size[1]
      return if room <= 0

      wanted = @scroll
      wanted = index - room + 1 if index >= wanted + room
      wanted = index if index < wanted

      scroll_to_row wanted
    end

    # Chooses row *index*, held inside what there is, and brings it into view.
    def select(index : Int32) : Nil
      count = @rows.size
      if count.zero?
        @selected = 0
        return
      end

      @selected = index.clamp 0, count - 1
      scroll_to @selected
    end

    # The chosen row, or `nil` when there are none.
    def current : T?
      return if @rows.empty?

      @rows.row @selected
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new 1, 1
    end

    # As tall as it has rows. A list sized to grow never uses this; one sized
    # to fit is as tall as what it holds, and asking costs one question.
    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @rows.size
    end

    # Answers a wheel notch, and lets everything else past.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      context.consume if scroll_wheel event
    end

    # Draws the rows that are showing, one view each.
    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      # A window that changed size brings the selection back rather than
      # leaving it off the edge a resize put it over.
      if view.height != @revealed_at
        @revealed_at = view.height
        scroll_to @selected
      end

      # Asked once a frame rather than once a row: the answer walks up to the
      # router, and it is the same answer for every row in the window.
      lit = focused?

      first = visible_range.begin
      each_visible do |index, item|
        row = view.view Rect.new(0, index - first, view.width, 1)
        draw_row row, index, item, index == @selected, lit
      end
    end

    private def draw_row(view : View, index : Int32, item : T, chosen : Bool,
                         lit : Bool) : Nil
      hook = @on_draw
      return hook.call view, index, item, chosen, lit if hook

      view.write 0, 0, item.to_s, chosen ? Style::DEFAULT.reverse : Style::DEFAULT
    end
  end
end
