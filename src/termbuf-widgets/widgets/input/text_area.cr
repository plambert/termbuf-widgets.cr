require "../../editing/editor"
require "../../message"
require "../../router"
require "../../widget"
require "./interactive"

module TermBuf::Widgets
  # A place to type more than one line.
  #
  #     area = TextArea.new "the first line\nthe second"
  #     area.wrap = Layout::Wrap::Words
  #     root.add area
  #
  # It is a `Field` with the two rules that make a field a field taken out.
  # `Enter` puts a line break in rather than handing the text over, and up and
  # down move the cursor between rows rather than walking a history. What hands
  # the text over is `#accept_keys`, which is a key the terminal can tell from
  # `Enter`; see `.default_accept_keys` for why there are two of them.
  #
  # The text lives in one `LineBuffer` with its breaks in it, the way it does
  # in a growing field, rather than in a list of lines. A cursor is one index
  # either way, and one index is what the editing model, the selection and the
  # kill ring are already written against; a list of lines would mean a second
  # cursor made of a row and a column, and two of everything that moves it.
  #
  # Rows here are what is drawn, not what was typed: a paragraph wrapped at the
  # right edge is several rows and one line. Up and down move by drawn row,
  # because that is where the cursor appears to be, and they keep the column
  # they started from, so walking down past a short row and on to a long one
  # comes back to where it began.
  class TextArea < Widget
    include Interactive

    # Which way the box grows to fit what is in it.
    enum Growth
      # Neither. The box is the size it is given and the text scrolls inside
      # it.
      Fixed

      # Widens to the longest line, and takes the height it is given.
      Horizontal

      # Grows downward as far as `TextArea#max_rows`, then scrolls.
      Vertical

      # Both.
      Both
    end

    # The text changed.
    struct Changed < Message
      # Which box it happened in.
      getter area : TextArea

      # What it now says.
      getter text : String

      def initialize(@area : TextArea, @text : String)
      end
    end

    # The text was handed over, which is what an accept key does. Unlike
    # `Field::Accepted` this leaves the text where it is: a text area is
    # usually one field of a form rather than a prompt that starts again.
    struct Accepted < Message
      # Which box it came from.
      getter area : TextArea

      # What was in it.
      getter text : String

      def initialize(@area : TextArea, @text : String)
      end
    end

    # `Enter`, bound to breaking the line rather than handing it over.
    NEWLINE_KEYMAP = Keymap(Editor::Action).build do |map|
      map.bind Key.parse("Enter"), "start a new line", Editor::Action::Newline
    end

    # The keys that move the cursor a row, which are answered here rather than
    # by the editor: the editor's vocabulary has no row in it, because a field
    # is one row and gives up and down to its history.
    UP   = Key.parse("Up").first
    DOWN = Key.parse("Down").first

    # Keys, bound to what they do to the text.
    getter editor : Editor

    # Where the lines are allowed to break.
    layout_property wrap : Layout::Wrap = Layout::Wrap::Words

    # Which way the box grows to fit what is in it.
    getter growth : Growth

    # Rows the box may grow to, before the border and anything around it.
    getter max_rows : Int32

    # What hands the text over.
    #
    # Every one of them emits `Accepted`. `Enter` is not among them and cannot
    # be: it is what puts a line break in.
    property accept_keys : Array(Key)

    # What selected text is drawn in.
    property selection_style : Style

    # Shown instead of the text when there is none.
    property placeholder : String?

    # What the placeholder is drawn in.
    property placeholder_style : Style

    # How clusters are measured, taken from the tree at every layout.
    getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

    # Rows the view has scrolled down by.
    getter row_offset : Int32 = 0

    # Cells the view has scrolled right by, which only a box that does not
    # wrap ever has.
    getter column_offset : Int32 = 0

    # The column an up or down key is aiming for, in cells, or `nil` when the
    # last key was not one of them.
    #
    # Walking down a long row, a short one and a long one again arrives back
    # where it started, because the short row moves the cursor without moving
    # what it is aiming at. Anything else at all clears it.
    @goal_column : Int32? = nil

    def initialize(text : String = "",
                   @editor : Editor = Editor.new,
                   wrap : Layout::Wrap = Layout::Wrap::Words,
                   @growth : Growth = Growth::Vertical,
                   @max_rows : Int32 = 8,
                   accept_keys : Array(Key)? = nil,
                   border : Border? = nil,
                   style : Style? = Style::DEFAULT,
                   @selection_style : Style = Style::DEFAULT.reverse,
                   @placeholder : String? = nil,
                   @placeholder_style : Style = Style::DEFAULT.faint)
      @wrap = wrap
      @accept_keys = accept_keys || TextArea.default_accept_keys
      @style = style
      @border = border
      @editor.multiline = true
      @editor.keymap = @editor.keymap.merge NEWLINE_KEYMAP
      apply_growth
      @editor.text = text unless text.empty?
    end

    # What hands the text over unless the application says otherwise.
    #
    # `Ctrl+Enter` is the key everyone reaches for, and a terminal has to be
    # speaking the kitty keyboard protocol to report it: `Enter` is the byte
    # `0x0D` and control does not change it, so on every other terminal
    # `Ctrl+Enter` arrives as a plain `Enter` and breaks the line. `Alt+Enter`
    # is the fallback rather than `Ctrl+D`, because the editing keymap already
    # spends `Ctrl+D` on end of input and rubbing out forward.
    def self.default_accept_keys : Array(Key)
      Key.parse("Ctrl+Enter") + Key.parse("Alt+Enter")
    end

    # Focus lands here: it is the widget that takes typing.
    def focusable? : Bool
      true
    end

    # The text as it stands, line breaks and all.
    def text : String
      @editor.text
    end

    # Replaces the text. Says nothing: a message is what the user did.
    def text=(value : String) : String
      @editor.text = value
      @goal_column = nil
      invalidate_layout
      value
    end

    # The text being edited.
    def buffer : LineBuffer
      @editor.buffer
    end

    # The text split at its line breaks.
    def lines : Array(String)
      buffer.lines
    end

    # Which way the box grows to fit what is in it.
    def growth=(value : Growth) : Growth
      return value if @growth == value

      @growth = value
      apply_growth
      value
    end

    # Rows the box may grow to.
    def max_rows=(rows : Int32) : Int32
      return rows if @max_rows == rows

      @max_rows = rows
      apply_growth
      rows
    end

    # ------------------------------------------------------------- events

    # Does whatever *key* is bound to and says what came of it.
    def press(key : Key) : Nil
      return hand_over if accepts? key
      return if move_row key

      @goal_column = nil
      before = text
      @editor.handle key
      invalidate_layout
      announce before
    end

    # Pasted text goes in as text, line breaks and all.
    def paste(text : String) : Nil
      @goal_column = nil
      before = self.text
      @editor.paste text
      invalidate_layout
      announce before
    end

    # Takes a key, a paste, or a click.
    #
    # A key is claimed, the way a field claims one: nothing above a text area
    # should see what was typed into it. A paste is not, because it is news
    # about the terminal as much as it is text.
    def handle(event : Event, context : Context) : Nil
      case event
      when Events::Key
        press event.key
        context.consume
      when Events::Paste
        paste event.text
      when Events::Mouse
        pointed event, context
      end
    end

    # Whether *key* is one of the keys that hands the text over.
    def accepts?(key : Key) : Bool
      normalised = Keymap::Alias.normalise key
      @accept_keys.any? { |accept| Keymap::Alias.normalise(accept) == normalised }
    end

    # Says the text was handed over. The text stays where it is.
    def hand_over : Nil
      emit Accepted.new self, text
    end

    # A click puts the keyboard here and the cursor where it landed.
    private def pointed(event : Events::Mouse, context : Context) : Nil
      return unless event.button.left? && event.action.press?
      return unless frame.contains? event.x, event.y

      take_focus context
      place_cursor event.x, event.y
      context.consume
    end

    # Puts the cursor under (*x*, *y*), which are in buffer coordinates.
    private def place_cursor(x : Int32, y : Int32) : Nil
      area = content
      return if area.empty?

      lines = rows
      row = (y - area.y + @row_offset).clamp 0, lines.size - 1
      cell = Math.max x - area.x + @column_offset, 0

      @goal_column = nil
      buffer.move_to cluster_in lines[row], cell
    end

    # Sends `Changed` when the text is not what it was.
    private def announce(before : String) : Nil
      after = text
      return if after == before

      emit Changed.new self, after
    end

    # Moves the cursor a row for *key*, answering whether it was one.
    #
    # A row at either end takes the key and does nothing with it rather than
    # letting it through, because what it would fall through to is the
    # editor's history walk.
    private def move_row(key : Key) : Bool
      step = case key
             when UP   then -1
             when DOWN then 1
             else           return false
             end

      lines = rows
      row, cell = cursor_cell
      goal = @goal_column || cell
      target = row + step

      buffer.move_to cluster_in lines[target], goal if 0 <= target < lines.size
      @goal_column = goal
      true
    end

    # The cluster *cells* into *range*, which is where a column lands on a row.
    #
    # A cluster the terminal draws double is not split: a column inside one
    # lands before it.
    private def cluster_in(range : Range(Int32, Int32), cells : Int32) : Int32
      used = 0
      index = range.begin

      while index < range.end
        width = buffer.width_at index
        break if used + width > cells

        used += width
        index += 1
      end

      index
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy

      # A cell for the cursor past the end of the longest line, so that typing
      # at the end of it does not put the cursor outside the box.
      Layout::Intrinsic.new 1, longest_line + 1
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy

      Math.max rows_in(width).size, 1
    end

    # Cells the widest line takes, ignoring where it would wrap.
    def longest_line : Int32
      widest = 0
      used = 0

      (0...buffer.size).each do |index|
        if buffer[index] == LineBuffer::NEWLINE
          widest = Math.max widest, used
          used = 0
          next
        end

        used += buffer.width_at index
      end

      Math.max widest, used
    end

    # Cells there is room for text in, as the box was laid out.
    def text_width : Int32
      content.width
    end

    # Where each drawn row starts and ends, in cluster indices.
    def rows : Array(Range(Int32, Int32))
      rows_in text_width
    end

    # Rows the text takes at *width*.
    def rows_in(width : Int32) : Array(Range(Int32, Int32))
      return hard_lines if @wrap.none? || width < 1

      wrapped width
    end

    # The rows of a box that never wraps: what was typed, split at its breaks.
    private def hard_lines : Array(Range(Int32, Int32))
      lines = [] of Range(Int32, Int32)
      start = 0

      (0...buffer.size).each do |index|
        next unless buffer[index] == LineBuffer::NEWLINE

        lines << (start...index)
        start = index + 1
      end

      lines << (start...buffer.size)
      lines
    end

    # The rows of a box that wraps at *width*.
    #
    # A break goes at the start of the word that did not fit under
    # `Layout::Wrap::Words`, and at the cluster that did not fit under
    # `Layout::Wrap::Anywhere`. A word too long for a row of its own is broken
    # at the edge either way, because the alternative is a row that overflows.
    private def wrapped(width : Int32) : Array(Range(Int32, Int32))
      lines = [] of Range(Int32, Int32)
      start = 0
      used = 0
      index = 0
      # Where the word being read began, which is where a row breaks under
      # `Layout::Wrap::Words`. The row's own start until a space has been seen,
      # so that a word too long for a row of its own breaks at the edge.
      word = 0
      spaced = false

      while index < buffer.size
        cluster = buffer[index] || ""

        if cluster == LineBuffer::NEWLINE
          lines << (start...index)
          index += 1
          start = index
          used = 0
          word = index
          spaced = false
          next
        end

        if blank? cluster
          spaced = true
        elsif spaced
          word = index
          spaced = false
        end

        cells = buffer.width_at index

        if used + cells > width && index > start
          cut = @wrap.words? && word > start ? word : index
          lines << (start...cut)
          start = cut
          used = buffer.width_between start, index
          word = cut
        end

        used += cells
        index += 1
      end

      lines << (start...buffer.size)
      # A cursor after a row that is exactly full belongs on the next row, and
      # that row has to exist for it to go there.
      lines << (buffer.size...buffer.size) if used == width && width > 0
      lines
    end

    private def blank?(cluster : String) : Bool
      char = cluster[0]?
      char ? char.whitespace? : false
    end

    # Which row the cursor is on and how many cells into it.
    def cursor_cell : {Int32, Int32}
      cursor = buffer.cursor
      lines = rows

      lines.each_with_index do |range, index|
        next if index < lines.size - 1 && beyond? cursor, range

        return {index, buffer.width_between range.begin, cursor}
      end

      last = lines.size - 1
      {last, buffer.width_between lines[last].begin, cursor}
    end

    # Whether *cursor* belongs to a row after *range*.
    #
    # The end of a row is the interesting case, and which row it is on depends
    # on why the row ended. A row that ran out of width is continued by the
    # next one, and a cursor at the end of it is about to type into the row
    # below; a row that ended at a line break is not, and a cursor at the end
    # of it is at the end of that line, where the user put it by pressing left.
    # Telling them apart is what the cluster after the row is: a break for one,
    # the next row's first cluster for the other.
    private def beyond?(cursor : Int32, range : Range(Int32, Int32)) : Bool
      return true if cursor > range.end
      return false if cursor < range.end

      buffer[range.end] != LineBuffer::NEWLINE
    end

    # Rows there is room to show.
    def visible_rows : Int32
      Math.max content.height, 1
    end

    # Keeps the cursor in view, scrolling by the least that does it.
    #
    # Worked out at every draw rather than at every keystroke, because how much
    # is in view depends on the rectangle and the rectangle is the layout's to
    # change.
    def reflow : Nil
      row, cell = cursor_cell
      height = visible_rows

      @row_offset = row if row < @row_offset
      @row_offset = row - height + 1 if row >= @row_offset + height
      @row_offset = Math.max @row_offset, 0

      return @column_offset = 0 unless @wrap.none?

      # A column is kept spare at the right, so that scrolling into view does
      # not put the cursor off the edge it was scrolled to.
      room = Math.max text_width - 1, 1
      @column_offset = cell if cell < @column_offset
      @column_offset = cell - room if cell > @column_offset + room
      @column_offset = Math.max @column_offset, 0
    end

    # Where the terminal's own cursor belongs, in the box the text is drawn in.
    def cursor_position : {Int32, Int32}?
      area = content
      return if area.empty?

      row, cell = cursor_cell

      {(cell - @column_offset).clamp(0, Math.max(area.width - 1, 0)),
       (row - @row_offset).clamp(0, Math.max(area.height - 1, 0))}
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      reflow
      return draw_placeholder view if buffer.empty?

      lines = rows
      shown = 0

      (@row_offset...lines.size).each do |index|
        break if shown >= view.height

        draw_clusters view, shown, lines[index]
        shown += 1
      end
    end

    private def draw_placeholder(view : View) : Nil
      text = @placeholder
      return unless text

      view.write 0, 0, Unicode.truncate(text, view.width, view.policy), @placeholder_style
    end

    # Writes *range* on row *y*, skipping what is off the left edge and
    # stopping at the right one.
    #
    # Clusters are gathered into runs of one style, so a row with nothing
    # selected costs one write rather than one per character. A cluster
    # straddling either edge is left out rather than halved: there is no half
    # of a wide character to draw.
    private def draw_clusters(view : View, y : Int32, range : Range(Int32, Int32)) : Nil
      selection = buffer.selection
      skip = @column_offset
      room = view.width
      column = 0
      run = String::Builder.new
      run_style = Style::DEFAULT
      run_x = 0

      range.each do |index|
        cells = buffer.width_at index
        start = column
        column += cells
        next if start < skip
        break if column - skip > room

        style = selection && selection.includes?(index) ? @selection_style : Style::DEFAULT
        at = start - skip

        if run.bytesize.zero?
          run_x = at
          run_style = style
        elsif style != run_style
          view.write run_x, y, run.to_s, run_style
          run = String::Builder.new
          run_x = at
          run_style = style
        end

        run << (buffer[index] || "")
      end

      text = run.to_s
      view.write run_x, y, text, run_style unless text.empty?
    end

    # The two sizings the growth mode comes to.
    private def apply_growth : Nil
      self.width = case @growth
                   in .horizontal?, .both? then Layout::Sizing.fit 1
                   in .fixed?, .vertical?  then Layout::Sizing.grow 1, 1
                   end

      self.height = case @growth
                    in .vertical?, .both?    then Layout::Sizing.fit 1, @max_rows
                    in .fixed?, .horizontal? then Layout::Sizing.grow 1, 1
                    end
    end
  end
end
