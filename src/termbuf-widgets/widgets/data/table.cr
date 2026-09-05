require "../../message"
require "../../widget"
require "../rows"
require "../scrolls"

module TermBuf::Widgets
  # Rows in columns, with a header that stays put while the rows scroll.
  #
  #     table = Table.new Rows.of(people)
  #     table.add_column "name", ->(person : Person) { person.name },
  #       Layout::Sizing.grow
  #     table.add_column "age", ->(person : Person) { person.age.to_s },
  #       Layout::Sizing.fixed(3), align: Unicode::Align::Right
  #
  # Like a `VirtualList` it holds no widget per row and no widget per cell: it
  # asks its `Rows` how many there are and then asks only for the ones in the
  # window, so a table of a million rows costs what a table of twenty does. A
  # cell is a string a column's block answers when the row is drawn, and
  # nothing is kept between frames.
  #
  # It is a `Scrolls` on both axes, so a `Scrollbar` attaches to either: one
  # beside it shows how far down the rows it has got, and one under it how far
  # across the columns.
  #
  # ### Widths
  #
  # A column is sized with a `Layout::Sizing`, resolved once per draw against
  # the width the table was laid out at:
  #
  # * `Layout::Sizing.fixed` takes exactly its cells.
  # * `Layout::Sizing.percent` takes that share of the room the gaps and the
  #   settled columns left, the settled ones being the fixed and the fitting,
  #   which is what a percent means everywhere else in the layout.
  # * `Layout::Sizing.fit` takes the width of its own header, which is the one
  #   thing that can be measured without asking for a row.
  # * `Layout::Sizing.grow` starts at its minimum and divides whatever is left
  #   over by weight, the last grower taking the remainder so the columns come
  #   to exactly the width available.
  #
  # Every result is held inside that sizing's own `min` and `max`. Auto-sizing
  # a column to its widest cell would mean asking for every row in the source,
  # which is the one thing a virtual table is built not to do, so it is not
  # offered.
  #
  # Columns wider than the table scroll sideways; `#scroll_by` moves them and
  # `#reveal_column` brings one into view.
  class Table(T) < Widget
    include Scrolls

    # The selection moved to another row.
    struct Selected < Message
      # Which row it is on, from zero.
      getter index : Int32

      def initialize(@index : Int32)
      end
    end

    # `Enter` was pressed on a row.
    struct Activated < Message
      # Which row it was on, from zero.
      getter index : Int32

      def initialize(@index : Int32)
      end
    end

    # One column: a header, a width, an alignment, and the block that answers
    # what a row has to say in it.
    #
    # The cell block is called when the row is drawn and never otherwise, so a
    # column that formats something expensive costs only the rows on screen.
    # `style` is asked at the same moment, for a column that colours itself by
    # what the row holds.
    class Column(U)
      # What is written above the column.
      getter header : String

      # How wide the column asks to be.
      getter sizing : Layout::Sizing

      # Which side of the cell the text sits on.
      getter align : Unicode::Align

      # What this column has to say about a row.
      getter cell : Proc(U, String)

      # What a cell is drawn in, or `nil` for the table's own style.
      getter style : Proc(U, Style)?

      def initialize(@header : String, @cell : Proc(U, String),
                     @sizing : Layout::Sizing = Layout::Sizing.grow,
                     @align : Unicode::Align = Unicode::Align::Left,
                     @style : Proc(U, Style)? = nil)
      end

      # What *item* has to say in this column.
      def text(item : U) : String
        @cell.call item
      end

      # What *item* is drawn in here, or `nil` when the column says nothing
      # about it.
      def style_for(item : U) : Style?
        @style.try &.call(item)
      end
    end

    # Where the rows come from.
    property rows : Rows(T)

    # The columns, left to right.
    layout_property columns : Array(Column(T)) = [] of Column(T)

    # Whether the header row is drawn.
    layout_property? header : Bool = true

    # Cells between one column and the next.
    layout_property column_gap : Int32 = 1

    # What the header is drawn in.
    property header_style : Style = Style::DEFAULT.bold

    # What the chosen row is drawn in, merged onto whatever a column said.
    property selected_style : Style = Style::DEFAULT.reverse

    # What marks a cell cut short.
    property ellipsis : String = "…"

    # Which row is chosen, from zero.
    getter selected : Int32 = 0

    # The first row showing.
    getter scroll : Int32 = 0

    # Cells the columns are scrolled left by.
    getter offset : Int32 = 0

    # How many cells one notch of the wheel moves.
    property wheel : Int32 = 3

    # How clusters are measured, taken from the tree at every layout.
    getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

    # The height the selection was last brought into view at, so a window that
    # changed size can bring it back without fighting a scroll somebody asked
    # for.
    @revealed_at : Int32 = -1

    def initialize(@rows : Rows(T),
                   columns : Array(Column(T)) = [] of Column(T),
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow(min: 1),
                   header : Bool = true,
                   column_gap : Int32 = 1,
                   selected : Int32 = 0,
                   style : Style? = nil)
      @columns = columns
      @width = width
      @height = height
      @header = header
      @column_gap = column_gap
      @selected = selected
      @style = style
      self.keymap = default_bindings
    end

    # Adds a column at the right and answers it.
    def add_column(column : Column(T)) : Column(T)
      @columns << column
      invalidate_layout
      column
    end

    # :ditto:
    def add_column(header : String, cell : Proc(T, String),
                   sizing : Layout::Sizing = Layout::Sizing.grow,
                   align : Unicode::Align = Unicode::Align::Left,
                   style : Proc(T, Style)? = nil) : Column(T)
      add_column Column(T).new(header, cell, sizing, align, style)
    end

    # Focus lands here: it is the widget the arrow keys are for.
    def focusable? : Bool
      true
    end

    # A table is a window on both axes: too many rows scrolls down, and
    # columns wider than it scroll across.
    def clip_x? : Bool
      true
    end

    # :ditto:
    def clip_y? : Bool
      true
    end

    # ------------------------------------------------------------- columns

    # Rows the header takes, which is one or none.
    def header_rows : Int32
      header? ? 1 : 0
    end

    # Cells each column is drawn in, at the width the table was laid out at.
    def column_widths : Array(Int32)
      widths_for content.width
    end

    # Cells each column would be drawn in, were the table *room* cells across.
    def widths_for(room : Int32) : Array(Int32)
      count = @columns.size
      return [] of Int32 if count.zero?

      widths = Array.new count, 0
      space = Math.max room - @column_gap * (count - 1), 0
      growers = [] of Int32
      shares = [] of Int32
      settled = 0

      @columns.each_with_index do |column, index|
        sizing = column.sizing
        widths[index] = case sizing.mode
                        in .fixed? then sizing.min
                        in .fit?   then sizing.clamp Unicode.string_width(column.header, @policy)
                        in .percent?
                          shares << index
                          0
                        in .grow?
                          growers << index
                          sizing.min
                        end
        settled += widths[index] unless sizing.grow?
      end

      taken = settled + share_out(widths, shares, Math.max(space - settled, 0))
      taken += growers.sum { |index| widths[index] }

      grow widths, growers, Math.max(space - taken, 0)
      widths
    end

    # Gives each percent column its share of *left*, which is the room the
    # settled columns did not take. Answers what they took between them.
    private def share_out(widths : Array(Int32), shares : Array(Int32), left : Int32) : Int32
      taken = 0

      shares.each do |index|
        sizing = @columns[index].sizing
        widths[index] = sizing.clamp left * sizing.weight // 100
        taken += widths[index]
      end

      taken
    end

    # Hands *leftover* to the growing columns by weight, left to right.
    #
    # What a column could not take, because its own maximum stopped it, is
    # left in the pot for the ones after it rather than lost, and the last
    # grower takes whatever is still there. That is what makes the columns
    # come to exactly the room there was.
    private def grow(widths : Array(Int32), growers : Array(Int32), leftover : Int32) : Nil
      return if growers.empty? || leftover <= 0

      weight = growers.sum { |index| @columns[index].sizing.weight }
      return if weight <= 0

      growers.each do |index|
        sizing = @columns[index].sizing
        share = weight <= sizing.weight ? leftover : leftover * sizing.weight // weight
        before = widths[index]
        widths[index] = sizing.clamp before + share
        leftover -= widths[index] - before
        weight -= sizing.weight
        break if leftover <= 0
      end
    end

    # Where column *index* starts, measured from the left of the first column.
    def column_left(widths : Array(Int32), index : Int32) : Int32
      left = 0
      index.times { |before| left += widths[before] + @column_gap }
      left
    end

    # Cells the columns come to, gaps included.
    def total_width : Int32
      widths = column_widths
      return 0 if widths.empty?

      widths.sum + @column_gap * (widths.size - 1)
    end

    # Which column the cells at *offset* from the left of the first column
    # falls in, or `nil` for one that falls in a gap or past the end.
    def column_at(offset : Int32) : Int32?
      widths = column_widths
      left = 0

      widths.each_with_index do |width, index|
        return index if left <= offset < left + width

        left += width + @column_gap
      end

      nil
    end

    # ------------------------------------------------------------ scrolling

    # Cells the columns come to, and rows there are.
    def content_size : {Int32, Int32}
      {total_width, @rows.size}
    end

    # Cells across, and rows that fit under the header.
    def viewport_size : {Int32, Int32}
      box = content
      {box.width, Math.max(box.height - header_rows, 0)}
    end

    # How many rows a page key moves, which is a window's worth.
    def page : Int32
      Math.max viewport_size[1], 1
    end

    # Cells the columns are scrolled left by.
    def scroll_x : Int32
      @offset
    end

    # The first row showing.
    def scroll_y : Int32
      @scroll
    end

    # Moves the window on either axis, stopping at the ends.
    def scroll_by(dx : Int32, dy : Int32) : Nil
      limit = max_scroll
      @offset = (@offset + dx).clamp 0, limit[0]
      @scroll = (@scroll + dy).clamp 0, limit[1]
    end

    # :ditto:
    def scroll_by(*, dx : Int32 = 0, dy : Int32 = 0) : Nil
      scroll_by dx, dy
    end

    # Moves the window down as little as it takes to show row *index*.
    def scroll_to(index : Int32) : Nil
      room = viewport_size[1]
      return if room <= 0

      wanted = @scroll
      wanted = index - room + 1 if index >= wanted + room
      wanted = index if index < wanted

      @scroll = wanted.clamp 0, max_scroll[1]
    end

    # Moves the window across as little as it takes to show column *index*.
    def reveal_column(index : Int32) : Nil
      widths = column_widths
      return unless 0 <= index < widths.size

      room = viewport_size[0]
      return if room <= 0

      left = column_left widths, index
      right = left + widths[index]
      wanted = @offset
      wanted = right - room if right > wanted + room
      wanted = left if left < wanted

      @offset = wanted.clamp 0, max_scroll[0]
    end

    # ------------------------------------------------------------ selection

    # The rows that are showing.
    def visible_range : Range(Int32, Int32)
      room = viewport_size[1]
      return (0...0) if room <= 0 || @rows.empty?

      first = @scroll.clamp 0, Math.max(@rows.size - 1, 0)
      (first...Math.min(first + room, @rows.size))
    end

    # Yields the index and the row of everything showing, top first.
    def each_visible(& : Int32, T ->) : Nil
      visible_range.each { |index| yield index, row_at(index) }
    end

    # What row *index* holds.
    #
    # Every read of the source goes through this, which is where a
    # `DataGrid` puts its sort order without the source knowing about it.
    def row_at(index : Int32) : T
      @rows.row index
    end

    # Chooses row *index*, held inside what there is, and brings it into view.
    #
    # Emits `Selected` when that moved the selection.
    def select(index : Int32) : Nil
      count = @rows.size
      if count.zero?
        @selected = 0
        return
      end

      wanted = index.clamp 0, count - 1
      moved = wanted != @selected
      @selected = wanted
      scroll_to @selected
      emit Selected.new(@selected) if moved
    end

    # The chosen row, or `nil` when there are none.
    def current : T?
      return if @rows.empty?

      row_at @selected
    end

    # Says the chosen row was activated, which is what `Enter` does.
    def activate : Nil
      return if @rows.empty?

      emit Activated.new(@selected)
    end

    # Whether row *index* is drawn as chosen.
    protected def row_selected?(index : Int32) : Bool
      index == @selected
    end

    # ------------------------------------------------------------- events

    # The keys a table answers. A table is given its own copy, so rebinding
    # one leaves the rest alone.
    protected def default_bindings : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Up"), "the row before", ->(_context : Context) { self.select selected - 1 }
        map.bind Key.parse("Down"), "the row after", ->(_context : Context) { self.select selected + 1 }
        map.bind Key.parse("PageUp"), "a window back", ->(_context : Context) { self.select selected - page }
        map.bind Key.parse("PageDown"), "a window on", ->(_context : Context) { self.select selected + page }
        map.bind Key.parse("Home"), "the first row", ->(_context : Context) { self.select 0 }
        map.bind Key.parse("End"), "the last row", ->(_context : Context) { self.select rows.size - 1 }
        map.bind Key.parse("Left"), "the columns back", ->(_context : Context) { scroll_by(-1, 0) }
        map.bind Key.parse("Right"), "the columns on", ->(_context : Context) { scroll_by 1, 0 }
        map.bind Key.parse("Enter"), "use this row", ->(_context : Context) { activate }
      end
    end

    # Which row (*x*, *y*) falls on, in buffer coordinates, or `nil` when it
    # falls on the header or outside the table.
    def row_at_point(x : Int32, y : Int32) : Int32?
      box = content
      return unless box.contains? x, y

      index = y - box.y - header_rows + @scroll
      return unless 0 <= index < @rows.size

      index
    end

    # Whether (*x*, *y*) falls on the header row.
    def header_at_point?(x : Int32, y : Int32) : Bool
      return false unless header?

      box = content
      box.contains?(x, y) && y == box.y
    end

    # Which column (*x*, *y*) falls on, or `nil` for a point in a gap or off
    # the table.
    def column_at_point(x : Int32, y : Int32) : Int32?
      box = content
      return unless box.contains? x, y

      column_at x - box.x + @offset
    end

    # Answers a wheel notch and a click on a row, and lets everything else
    # past.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      if scroll_wheel event
        context.consume
        return
      end

      return unless event.action.press? && event.button.left?

      index = row_at_point event.x, event.y
      return unless index

      self.select index
      context.consume
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy
      wanted = Math.max natural_width, 1

      Layout::Intrinsic.new 1, wanted
    end

    # Cells the columns come to when nothing is compressed: what a fixed
    # column asks for, what a fit column's header takes, and what a growing
    # column will not go under.
    def natural_width : Int32
      return 0 if @columns.empty?

      cells = @columns.sum do |column|
        sizing = column.sizing
        case sizing.mode
        in .fixed?, .grow?, .percent? then sizing.min
        in .fit?                      then sizing.clamp Unicode.string_width(column.header, @policy)
        end
      end

      cells + @column_gap * (@columns.size - 1)
    end

    # The header and a row apiece. A table sized to grow never uses this; one
    # sized to fit is as tall as what it holds, and asking costs no rows.
    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy
      header_rows + @rows.size
    end

    # ------------------------------------------------------------ drawing

    # Draws the header and the rows that are showing.
    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      @policy = view.policy

      # A window that changed size brings the selection back rather than
      # leaving it off the edge a resize put it over.
      if view.height != @revealed_at
        @revealed_at = view.height
        scroll_to @selected
      end

      widths = widths_for view.width
      return if widths.empty?

      draw_header view, widths if header?

      top = header_rows
      first = visible_range.begin
      each_visible do |index, item|
        row = top + index - first
        break if row >= view.height

        draw_row view, widths, row, index, item
      end
    end

    private def draw_header(view : View, widths : Array(Int32)) : Nil
      each_span view, widths do |index, column, left, start, stop|
        text = fitted column.header, widths[index], column.align, view.policy
        write view, text, left, start, stop, 0, @header_style
      end
    end

    private def draw_row(view : View, widths : Array(Int32), row : Int32,
                         index : Int32, item : T) : Nil
      view.fill Rect.new(0, row, view.width, 1), ' ', @selected_style if row_selected? index

      each_span view, widths do |column_index, column, left, start, stop|
        text = fitted column.text(item), widths[column_index], column.align, view.policy
        write view, text, left, start, stop, row, cell_style(index, column_index, item)
      end
    end

    # What cell (*index*, *column*) is drawn in.
    protected def cell_style(index : Int32, column : Int32, item : T) : Style
      base = @columns[column].style_for(item) || Style::DEFAULT
      row_selected?(index) ? base.merge(@selected_style) : base
    end

    # Yields every column with any of itself showing: its index, the column,
    # where the column starts, and where its visible part starts and stops.
    # All three are measured from the left of the first column.
    private def each_span(view : View, widths : Array(Int32),
                          & : Int32, Column(T), Int32, Int32, Int32 ->) : Nil
      left = 0
      right = @offset + view.width

      widths.each_with_index do |width, index|
        start = Math.max left, @offset
        stop = Math.min left + width, right
        here = left
        left += width + @column_gap
        next if stop <= start

        yield index, @columns[index], here, start, stop
      end
    end

    # *text* cut to *width* cells with an ellipsis and padded back out to it,
    # so the column lines up whatever the row says.
    private def fitted(text : String, width : Int32, align : Unicode::Align,
                       policy : Unicode::WidthPolicy) : String
      Unicode.fit Unicode.ellipsize(text, width, @ellipsis, policy), width, align, ' ', policy
    end

    # Writes the part of *text* between *start* and *stop* at row *y*, where
    # *text* starts at *left* and the view starts at `#offset`. All three
    # columns are measured from the left of the first column.
    private def write(view : View, text : String, left : Int32, start : Int32,
                      stop : Int32, y : Int32, style : Style) : Nil
      piece = Unicode.window text, start - left, stop - start, view.policy
      return if piece.empty?

      view.write start - @offset, y, piece, style
    end
  end
end
