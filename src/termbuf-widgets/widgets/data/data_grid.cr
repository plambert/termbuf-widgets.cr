require "../field"
require "./table"

module TermBuf::Widgets
  # A `Table` with a cell under the keyboard rather than only a row.
  #
  #     grid = DataGrid.new Rows.of(records)
  #     grid.add_column "name", ->(record : Record) { record.name }
  #     grid.selection = DataGrid::Selection::Cell
  #
  # Three things the table has not:
  #
  # * **A focused column.** `Left` and `Right` move it instead of scrolling,
  #   bringing it into view as they go, and a click puts it under the pointer.
  # * **Editing in place.** `Enter` opens a `Field` over the cell, `Enter`
  #   commits and `Escape` abandons, and a commit emits `Edited`. Nothing is
  #   written back to the source: the grid says what was typed and where, and
  #   whatever owns the data decides what that means.
  # * **A sort order.** `#sort_by` builds a map from the order on screen to
  #   the order in the source and reads every row through it, so the `Rows`
  #   are never touched and never asked to be sortable. Sorting is the one
  #   thing here that asks for every row: the keys have to be compared, and
  #   there is no way to compare what has not been read.
  #
  # Indices in messages and in `#selected_indices` are the source's, not the
  # order on screen, so they still mean the same row after a sort.
  class DataGrid(T) < Table(T)
    # What a selection covers.
    enum Selection
      # A whole row at a time, which is what a `Table` does.
      Row

      # One cell: the row under the selection and the focused column.
      Cell

      # Any number of rows, toggled with the space bar.
      Multi
    end

    # Which way a sort runs.
    enum Order
      Ascending
      Descending

      # The other one, which is what clicking a header twice gives.
      def reverse : Order
        ascending? ? Descending : Ascending
      end
    end

    # A cell was edited and the edit was committed.
    struct Edited < Message
      # Which row, counted in the source rather than on screen.
      getter row : Int32

      # Which column, from zero.
      getter column : Int32

      # What was typed.
      getter text : String

      def initialize(@row : Int32, @column : Int32, @text : String)
      end
    end

    # What a selection covers.
    property selection : Selection = Selection::Row

    # Whether `Enter` opens an editor. A grid told otherwise activates the row
    # the way a `Table` does.
    property? editable : Bool = true

    # What the focused cell is drawn in, merged onto whatever the column said.
    property focus_style : Style = Style::DEFAULT.reverse

    # Which column the keyboard is on, from zero.
    getter focused_column : Int32 = 0

    # Which column the rows are sorted by, or `nil` for the source's own
    # order.
    getter sort_column : Int32? = nil

    # Which way that sort runs.
    getter sort_direction : Order = Order::Ascending

    # The editor over the focused cell, or `nil` when nothing is being
    # edited.
    getter field : Field? = nil

    # Screen order to source order, or `nil` when the two are the same.
    @order : Array(Int32)? = nil

    # Rows picked in `Selection::Multi`, by source index.
    @picked = Set(Int32).new

    # The keys put away while the editor has them.
    @held : Bindings? = nil

    # ------------------------------------------------------------ the cell

    # Puts the keyboard on column *index*, held inside the columns there are,
    # and brings it into view.
    def focus_column(index : Int32) : Nil
      return if columns.empty?

      @focused_column = index.clamp 0, columns.size - 1
      reveal_column @focused_column
    end

    # The column the keyboard is on, or `nil` when there are none.
    def current_column : Column(T)?
      columns[@focused_column]?
    end

    # ---------------------------------------------------------- the source

    # What row *index* holds, read through the sort order.
    def row_at(index : Int32) : T
      rows.row source_index(index)
    end

    # Where the row shown at *index* sits in the source.
    def source_index(index : Int32) : Int32
      order = @order
      return index unless order

      order[index]? || index
    end

    # Where the source's row *index* is shown, or `nil` when it is not.
    def screen_index(index : Int32) : Int32?
      order = @order
      return index unless order

      order.index index
    end

    # Sorts the rows by what *column* says about them.
    #
    # Stable: rows whose cells compare equal keep the order the source had
    # them in, whichever way the sort runs. The source is left alone; what is
    # built is a map from the order on screen to the order in it, and every
    # read goes through that.
    #
    # This asks the source for every row once. It is the one thing here that
    # does, and a source too large to read through is a source to sort at its
    # own end rather than here.
    def sort_by(column : Int32, direction : Order = Order::Ascending) : Nil
      raise IndexError.new "no column #{column} to sort by" unless 0 <= column < columns.size

      held = rows.empty? ? nil : source_index(selected)
      @sort_column = column
      @sort_direction = direction
      @order = order_for column, direction
      restore held
    end

    # Sorts by the focused column, turning the sort around when it is already
    # the one being sorted by. What a click on a header does.
    def sort_by_focus : Nil
      column = @focused_column
      return if columns.empty?

      sort_by column, column == @sort_column ? @sort_direction.reverse : Order::Ascending
    end

    # Puts the rows back in the order the source has them.
    def clear_sort : Nil
      return unless @sort_column

      held = rows.empty? ? nil : source_index(selected)
      @sort_column = nil
      @order = nil
      restore held
    end

    private def order_for(column : Int32, direction : Order) : Array(Int32)
      found = columns[column]
      keyed = Array.new(rows.size) { |position| {found.text(rows.row(position)), position} }

      keyed.sort! do |a, b|
        first = a[0] <=> b[0]
        next a[1] <=> b[1] if first.zero?

        direction.ascending? ? first : -first
      end

      keyed.map &.[1]
    end

    # Puts the selection back on the source row it was on.
    private def restore(source : Int32?) : Nil
      return unless source

      found = screen_index source
      self.select found if found
    end

    # ------------------------------------------------------------ picking

    # The rows that are selected, by source index and in source order.
    #
    # One row in `Selection::Row` and `Selection::Cell`, and whatever has been
    # picked in `Selection::Multi`.
    def selected_indices : Array(Int32)
      case @selection
      in .row?, .cell? then rows.empty? ? [] of Int32 : [source_index(selected)]
      in .multi?       then @picked.to_a.sort!
      end
    end

    # Adds the row on screen at *index* to the picked ones, or takes it out
    # again. Only `Selection::Multi` picks more than one row.
    def toggle(index : Int32) : Nil
      return if rows.empty?

      source = source_index index
      if @picked.includes? source
        @picked.delete source
      else
        @picked << source
      end
    end

    # Picks nothing at all.
    def clear_picked : Nil
      @picked.clear
    end

    protected def row_selected?(index : Int32) : Bool
      case @selection
      in .row?   then index == selected
      in .cell?  then false
      in .multi? then @picked.includes?(source_index(index)) || index == selected
      end
    end

    protected def cell_style(index : Int32, column : Int32, item : T) : Style
      base = super
      return base unless @selection.cell? && index == selected && column == @focused_column

      base.merge @focus_style
    end

    # ------------------------------------------------------------ editing

    # Whether a cell is being edited.
    def editing? : Bool
      !@field.nil?
    end

    # Opens an editor over the focused cell.
    #
    # The grid's own keys are put away while it is open, so `Enter` and the
    # arrows belong to what is being typed rather than to the selection.
    # *context* is what moves the keyboard onto the editor; without one the
    # editor opens unfocused, which is what a caller driving the grid itself
    # wants.
    def edit(context : Context? = nil) : Nil
      return if editing? || rows.empty? || columns.empty?

      widths = column_widths
      column = @focused_column.clamp 0, widths.size - 1
      made = Field.new
      made.text = columns[column].text(row_at(selected))
      made.width = Layout::Sizing.fixed Math.max(widths[column], 1)
      made.height = Layout::Sizing.fixed 1
      made.floating = Layout::Floating.on self,
        dx: cell_column(widths, column), dy: cell_row, z: 1,
        overflow: Layout::Overflow::Clamp

      add made
      @field = made
      @held = keymap
      self.keymap = nil
      context.try &.focus.focus(made)
    end

    # Takes the editor away without committing anything.
    def cancel_edit(context : Context? = nil) : Nil
      made = @field
      return unless made

      remove made
      @field = nil
      self.keymap = @held
      @held = nil
      context.try &.focus.focus(self)
    end

    # Where the focused cell starts, from the left of the grid's own
    # rectangle.
    private def cell_column(widths : Array(Int32), column : Int32) : Int32
      content.x - rect.x + column_left(widths, column) - offset
    end

    # :ditto: from the top of it.
    private def cell_row : Int32
      content.y - rect.y + header_rows + selected - scroll
    end

    # ------------------------------------------------------------- events

    protected def default_bindings : Bindings
      super.merge(Bindings.build do |map|
        map.bind Key.parse("Left"), "the cell to the left",
          ->(_context : Context) { focus_column focused_column - 1 }
        map.bind Key.parse("Right"), "the cell to the right",
          ->(_context : Context) { focus_column focused_column + 1 }
        map.bind Key.parse("Enter"), "edit this cell",
          ->(context : Context) { editable? ? edit(context) : activate }
        map.bind Key.character(' '), "pick this row as well",
          ->(_context : Context) { toggle selected }
        map.bind Key.parse("s"), "sort by this column",
          ->(_context : Context) { sort_by_focus }
      end)
    end

    # Answers what the editor has to say, a click on a header, and everything
    # a `Table` answers.
    def handle(event : Event, context : Context) : Nil
      case event
      when Field::Accepted  then commit event.text, context
      when Field::Cancelled then abandon context
      when Events::Mouse
        return if sorted_by_header event, context

        aim_at event
        super
      end
    end

    private def commit(text : String, context : Context) : Nil
      return unless editing?

      row = source_index selected
      column = @focused_column
      cancel_edit context
      emit Edited.new(row, column, text)
      context.consume
    end

    private def abandon(context : Context) : Nil
      return unless editing?

      cancel_edit context
      context.consume
    end

    # Whether a press on a column's header sorted the rows by it.
    private def sorted_by_header(event : Events::Mouse, context : Context) : Bool
      return false unless press? event
      return false unless header_at_point? event.x, event.y

      column = column_at_point event.x, event.y
      return false unless column

      focus_column column
      sort_by_focus
      context.consume
      true
    end

    # Puts the keyboard on the column a press landed in, before the table
    # takes the press as a choice of row.
    private def aim_at(event : Events::Mouse) : Nil
      return unless press? event
      return unless row_at_point event.x, event.y

      column = column_at_point event.x, event.y
      focus_column column if column
    end

    private def press?(event : Events::Mouse) : Bool
      event.action.press? && event.button.left?
    end
  end
end
