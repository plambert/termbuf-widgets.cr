require "../../message"
require "../../router"
require "../../widget"
require "../panel"
require "../input/interactive"

module TermBuf::Widgets
  # A strip of tabs over a panel showing one of them at a time.
  #
  #     panels = TabbedPanels.new
  #     panels.add "source", editor
  #     panels.add "output", log, closable: true
  #     panels.activate 1
  #
  # The tabs that are not showing are hidden widgets, so the layout engine
  # skips them entirely: a program with twenty tabs open lays out one of them
  # per frame. Nothing is thrown away by hiding one, so a tab comes back with
  # its scroll position and its typing where they were left.
  #
  # `Ctrl+PageDown` and `Ctrl+PageUp` move between tabs from anywhere inside
  # the panels, and moving takes the keyboard into whatever is now showing.
  # `#previous_keys` and `#next_keys` take other keys for the same thing. The
  # strip itself takes the keyboard too, where the arrows along it move between
  # tabs and `Enter` steps down into the tab.
  class TabbedPanels < Widget
    # The tab showing has changed.
    struct Changed < Message
      # Which panels it happened in, since one handler usually answers
      # several.
      getter panels : TabbedPanels

      # Which tab is showing now, counting from zero.
      getter index : Int32

      # The tab itself.
      getter tab : Tab

      def initialize(@panels : TabbedPanels, @index : Int32, @tab : Tab)
      end
    end

    # A tab was closed through its close glyph.
    struct Closed < Message
      # Which panels it happened in.
      getter panels : TabbedPanels

      # Where the tab was, counting from zero.
      getter index : Int32

      # The tab that is gone, and the widget that was under it.
      getter tab : Tab

      def initialize(@panels : TabbedPanels, @index : Int32, @tab : Tab)
      end
    end

    # One tab: what the strip says, and what the panel shows.
    class Tab
      # What the strip says.
      property title : String

      # What is shown while this tab is the one showing.
      getter widget : Widget

      # Whether the strip draws a close glyph for it.
      property? closable : Bool

      def initialize(@title : String, @widget : Widget, @closable : Bool = false)
      end
    end

    # The keys that move to the tab before this one unless told otherwise.
    DEFAULT_PREVIOUS = ["Ctrl+PageUp"]

    # :ditto: for the one after.
    DEFAULT_NEXT = ["Ctrl+PageDown"]

    # The tabs, in the order they were added.
    getter tabs = [] of Tab

    # Which tab is showing, counting from zero.
    getter active : Int32 = 0

    # The strip the titles are drawn on, which is this widget's first child.
    getter strip : Strip

    # The panel the tabs' widgets sit in, which is its second.
    getter body : Panel

    # The keys that move to the tab before this one.
    getter previous_keys : Array(String)

    # The keys that move to the one after.
    getter next_keys : Array(String)

    def initialize(direction : Layout::Direction = Layout::Direction::Column,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow,
                   border : Border? = nil,
                   style : Style? = nil)
      @previous_keys = DEFAULT_PREVIOUS.dup
      @next_keys = DEFAULT_NEXT.dup
      @direction = direction
      @width = width
      @height = height
      @style = style
      @strip = Strip.new
      @body = Panel.new width: Layout::Sizing.grow, height: Layout::Sizing.grow,
        border: border
      add @strip
      add @body
      lay_out
      rebind
    end

    # ------------------------------------------------------------- tabs

    # Adds a tab showing *widget* and answers it.
    def add(title : String, widget : Widget, closable : Bool = false) : Tab
      tab = Tab.new title, widget, closable
      @tabs << tab
      @body.add widget
      show_active
      invalidate_layout
      tab
    end

    # Takes the tab at *index* out, answering it, or `nil` when there was none
    # there. The widget under it comes out of the tree with it.
    def remove(index : Int32) : Tab?
      return unless tab? index

      tab = @tabs.delete_at index
      @body.remove tab.widget
      @active = @active.clamp 0, Math.max(@tabs.size - 1, 0)
      show_active
      invalidate_layout
      tab
    end

    # The tab showing, or `nil` when there are none.
    def active_tab : Tab?
      @tabs[@active]?
    end

    # Whether *index* names a tab.
    def tab?(index : Int32) : Bool
      0 <= index < @tabs.size
    end

    # --------------------------------------------------------- activating

    # Shows the tab at *index* and says `Changed` when that is a different one.
    #
    # Unlike a property being set, this is the verb: a key, a click and an
    # application changing pages all come through here, so this is where the
    # message belongs.
    def activate(index : Int32) : Nil
      return unless tab? index
      return if index == @active && settled?

      @active = index
      show_active
      emit Changed.new self, index, @tabs[index]
    end

    # Shows the tab *step* places along, wrapping at either end.
    def step(step : Int32) : Nil
      return if @tabs.empty?

      activate (@active + step) % @tabs.size
    end

    # Closes the tab at *index*, saying `Closed` when there was one there.
    def close(index : Int32) : Nil
      tab = remove index
      return unless tab

      emit Closed.new self, index, tab
    end

    # Puts the keyboard on the first thing inside the tab that is showing,
    # answering whether there was anything there to take it.
    def focus_active(context : Context) : Bool
      tab = active_tab
      return false unless tab

      target = first_focusable tab.widget
      return false unless target

      context.focus.focus target
    end

    # Whether the widgets' hidden flags already say what `#active` says.
    private def settled? : Bool
      @tabs.each_with_index do |tab, index|
        return false if tab.widget.hidden? == (index == @active)
      end

      true
    end

    # Hides every tab's widget but the one showing.
    private def show_active : Nil
      @tabs.each_with_index { |tab, index| tab.widget.hidden = index != @active }
    end

    # The first thing under *widget* the keyboard can land on, *widget* itself
    # included.
    private def first_focusable(widget : Widget) : Widget?
      return if widget.hidden?
      return widget if widget.focusable?

      widget.children.each do |child|
        found = first_focusable child
        return found if found
      end

      nil
    end

    # -------------------------------------------------------------- keys

    # Takes other keys for the tab before this one.
    def previous_keys=(keys : Enumerable(String)) : Array(String)
      @previous_keys = keys.to_a
      rebind
      @previous_keys
    end

    # :ditto: for the one after.
    def next_keys=(keys : Enumerable(String)) : Array(String)
      @next_keys = keys.to_a
      rebind
      @next_keys
    end

    # Which way the strip runs: across the top of a column of panels, down the
    # side of a row of them.
    def direction=(value : Layout::Direction) : Layout::Direction
      result = super
      lay_out
      result
    end

    private def rebind : Nil
      self.keymap = Bindings.build do |map|
        @previous_keys.each do |key|
          map.bind Key.parse(key), "the tab before",
            ->(context : Context) { step(-1); focus_active context; nil }
        end

        @next_keys.each do |key|
          map.bind Key.parse(key), "the tab after",
            ->(context : Context) { step 1; focus_active context; nil }
        end
      end
    end

    # A strip above a column of panels runs across; one beside a row of them
    # runs down.
    private def lay_out : Nil
      @strip.direction = case @direction
                         in .column? then Layout::Direction::Row
                         in .row?    then Layout::Direction::Column
                         end
    end

    # A strip of titles, one of them the tab that is showing.
    #
    # The strip draws its own titles rather than holding a widget each, for the
    # reason a `NavigationBar` does: which titles are cut, and by how much, is
    # a decision about the whole strip.
    #
    # It reads the tabs off the `TabbedPanels` it was added to rather than
    # holding one, which is what keeps there being one list of tabs rather than
    # two that have to be kept in step. A strip outside a `TabbedPanels` has no
    # tabs and draws nothing.
    class Strip < Widget
      include Interactive

      # The glyph that closes a tab on a terminal that measures it at one cell.
      CLOSE = "×"

      # What stands in for it where it does not come out at one cell.
      CLOSE_ASCII = "x"

      # What a strip with no panels above it draws.
      NO_TABS = [] of Tab

      # Where one title was drawn, in buffer coordinates.
      record Span, index : Int32, x : Int32, y : Int32, width : Int32, close : Int32 do
        # Whether (*x*, *y*) falls on this title.
        def holds?(x : Int32, y : Int32) : Bool
          y == @y && @x <= x < @x + @width
        end

        # Whether it falls on this title's close glyph.
        def closing?(x : Int32, y : Int32) : Bool
          @close >= 0 && y == @y && x == @x + @close
        end
      end

      # Cells of space either side of a title.
      layout_property title_padding : Int32 = 1

      # What a tab that is not showing is drawn in.
      property tab_style : Style = Style::DEFAULT.faint

      # What the tab showing is drawn in while the strip has the keyboard.
      property focused_style : Style = Style::DEFAULT.reverse

      # What it is drawn in while the strip does not.
      property active_style : Style = Style::DEFAULT.bold

      @spans = [] of Span

      def initialize(style : Style? = nil)
        @style = style
        @direction = Layout::Direction::Row
        resize
        bind_arrows
      end

      # The panels this strip belongs to, or `nil` for one not in a tree.
      def panels? : TabbedPanels?
        parent.as? TabbedPanels
      end

      # The tabs to draw, which is none until the strip has been added to a
      # `TabbedPanels`.
      def tabs : Array(Tab)
        held = panels?
        held ? held.tabs : NO_TABS
      end

      # Which tab is showing, or -1 when the strip has no panels.
      def active : Int32
        held = panels?
        held ? held.active : -1
      end

      # Focus lands on the strip, which is what the arrows along it move.
      def focusable? : Bool
        true
      end

      # Which way the titles run, and with them which arrows move between
      # them and which way the strip grows.
      def direction=(value : Layout::Direction) : Layout::Direction
        result = super
        resize
        bind_arrows
        result
      end

      # The title drawn at (*x*, *y*) in buffer coordinates, as the last frame
      # drew it, or `nil` when the point is not on one.
      def tab_at(x : Int32, y : Int32) : Int32?
        @spans.find(&.holds?(x, y)).try &.index
      end

      # Whether (*x*, *y*) falls on a close glyph, and whose.
      def close_at(x : Int32, y : Int32) : Int32?
        @spans.find(&.closing?(x, y)).try &.index
      end

      def handle(event : Event, context : Context) : Nil
        return unless event.is_a? Events::Mouse

        clicked event, context do
          held = panels?
          next unless held

          take_focus context
          closing = close_at event.x, event.y
          next held.close closing if closing

          index = tab_at event.x, event.y
          held.activate index if index
        end
      end

      # -------------------------------------------------------- measuring

      # The glyph a closable tab is closed by under *policy*.
      def close_glyph(policy : Unicode::WidthPolicy) : String
        Glyphs.single_cell?({CLOSE}, policy) ? CLOSE : CLOSE_ASCII
      end

      # What one tab reads as on the strip, its padding and its close glyph
      # included.
      def cell_of(tab : Tab, policy : Unicode::WidthPolicy) : String
        pad = " " * @title_padding
        return "#{pad}#{tab.title}#{pad}" unless tab.closable?

        "#{pad}#{tab.title} #{close_glyph policy}#{pad}"
      end

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        widths = tabs.map { |tab| Unicode.string_width cell_of(tab, policy), policy }
        return Layout::Intrinsic.new 0, 0 if widths.empty?

        case @direction
        in .row?    then Layout::Intrinsic.new Math.min(widths.min, 1), widths.sum
        in .column? then Layout::Intrinsic.exact widths.max
        end
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        case @direction
        in .row?    then 1
        in .column? then tabs.size
        end
      end

      # --------------------------------------------------------- drawing

      def draw(view : View) : Nil
        @spans.clear
        return if view.width <= 0 || view.height <= 0

        case @direction
        in .row?    then draw_across view
        in .column? then draw_down view
        end
      end

      private def draw_across(view : View) : Nil
        column = 0

        tabs.each_with_index do |tab, index|
          break if column >= view.width

          column += write_cell view, column, 0, tab, index
        end
      end

      private def draw_down(view : View) : Nil
        tabs.each_with_index do |tab, index|
          break if index >= view.height

          write_cell view, 0, index, tab, index
        end
      end

      # Writes one title and answers how many columns it took.
      private def write_cell(view : View, column : Int32, row : Int32, tab : Tab,
                             index : Int32) : Int32
        text = cell_of tab, view.policy
        shown = Unicode.truncate text, Math.max(view.width - column, 0), view.policy
        view.write column, row, shown, style_for(index)

        width = Unicode.string_width shown, view.policy
        remember index, column, row, width, close_offset(tab, text, shown, view.policy)
        width
      end

      # Where the close glyph sits in a cell, counting from its left edge, or
      # -1 for a tab that has none and for one whose cell was cut short of it.
      private def close_offset(tab : Tab, text : String, shown : String,
                               policy : Unicode::WidthPolicy) : Int32
        return -1 unless tab.closable?

        whole = Unicode.string_width text, policy
        return -1 unless Unicode.string_width(shown, policy) == whole

        whole - @title_padding - Unicode.string_width(close_glyph(policy), policy)
      end

      private def remember(index : Int32, column : Int32, row : Int32, width : Int32,
                           close : Int32) : Nil
        box = content
        @spans << Span.new(index, box.x + column, box.y + row, width, close)
      end

      private def style_for(index : Int32) : Style
        return @tab_style unless index == active

        focused? ? @focused_style : @active_style
      end

      # A strip running across grows sideways and is one row thick; one
      # running down is the other way about.
      private def resize : Nil
        case @direction
        in .row?
          @width = Layout::Sizing.grow
          @height = Layout::Sizing.fit
        in .column?
          @width = Layout::Sizing.fit
          @height = Layout::Sizing.grow
        end
      end

      private def bind_arrows : Nil
        back, on = case @direction
                   in .row?    then {"Left", "Right"}
                   in .column? then {"Up", "Down"}
                   end

        self.keymap = Bindings.build do |map|
          map.bind Key.parse(back), "the tab before",
            ->(_context : Context) { panels?.try &.step(-1); nil }
          map.bind Key.parse(on), "the tab after",
            ->(_context : Context) { panels?.try &.step(1); nil }
          map.bind Key.parse("Enter"), "into the tab",
            ->(context : Context) { panels?.try &.focus_active(context); nil }
        end
      end
    end
  end
end
