require "../editing/editor"
require "../message"
require "../widget"
require "./border"

module TermBuf::Widgets
  # A place to type.
  #
  # The field is a widget: the layout gives it a rectangle, it says how tall it
  # would like to be at the width it was given, and it draws into the box
  # inside its own border. Nothing here owns a loop or a terminal.
  #
  #     field = Field.new prompt: Field::Prompt.new("> ")
  #     root.add field
  #
  # What comes of typing arrives as a message: `Accepted` carries the line,
  # `Cancelled` says it was abandoned, `EndOfInput` says there is no more
  # coming. A parent answers them in `Widget#handle`.
  class Field < Widget
    # What happens when the text outgrows one row.
    enum Growth
      # One row, scrolling sideways, with a marker where text runs off.
      Fixed

      # Wrap and grow to `Field#max_rows`, then scroll.
      Grow
    end

    # The line was handed over. Sent for `Editor::Outcome::Accepted`.
    struct Accepted < Message
      # What was entered.
      getter text : String

      def initialize(@text : String)
      end
    end

    # The line was abandoned.
    struct Cancelled < Message
    end

    # There is no more input coming, which is what `Ctrl+D` on an empty line
    # means.
    struct EndOfInput < Message
    end

    # What sits in front of the text.
    record Prompt,
      text : String,
      style : Style = Style::DEFAULT,
      # What the rows after the first get, so a wrapped line stays aligned
      # under the one before it. Spaces the width of *text* when `nil`.
      continuation : String? = nil

    # Shown where text has run off the left or right of a fixed field.
    MARKERS = {'<', '>'}

    # The completion key, which is `Tab` unless something rebinds it.
    COMPLETE = Key.named Key::Name::Tab

    # Keys, bound to what they do to the text.
    getter editor : Editor

    # Drawn in front of the text, or `nil` for none.
    property prompt : Prompt?

    # What happens when the text outgrows one row.
    property growth : Growth

    # Rows the panel may grow to, border included.
    getter max_rows : Int32

    # What selected text is drawn in.
    property selection_style : Style

    # Shown instead of the text when there is none.
    property placeholder : String?

    # What the placeholder is drawn in.
    property placeholder_style : Style

    # How clusters are measured, taken from the tree at every layout.
    getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

    # Where the view has scrolled to: cells for a fixed field, rows for one
    # that grows.
    getter offset : Int32 = 0

    def initialize(@editor : Editor = Editor.new,
                   border : Border? = nil,
                   @prompt : Prompt? = nil,
                   @growth : Growth = Growth::Fixed,
                   @max_rows : Int32 = 8,
                   style : Style? = Style::DEFAULT,
                   @selection_style : Style = Style::DEFAULT.reverse,
                   @placeholder : String? = nil,
                   @placeholder_style : Style = Style::DEFAULT.faint)
      @editor.multiline = @growth.grow?
      @style = style
      @border = border
      @width = Layout::Sizing.grow
      @height = Layout::Sizing.fit max: @max_rows
      claim_completion_key
    end

    # Focus lands here: it is the widget that takes typing.
    def focusable? : Bool
      true
    end

    # The line as it stands.
    def text : String
      @editor.text
    end

    # Replaces the line, ending any history walk.
    def text=(value : String) : String
      @editor.text = value
      invalidate_layout
      value
    end

    # The text being edited.
    def buffer : LineBuffer
      @editor.buffer
    end

    # What to ask when someone presses the completion key, or `nil` for a
    # field that does not complete.
    #
    # Setting this is what decides whether the field claims `Tab`; see
    # `#claim_completion_key`.
    def completions=(hook : Completion::Hook?) : Completion::Hook?
      @editor.completions = hook
      claim_completion_key
      hook
    end

    # :ditto:
    def completions : Completion::Hook?
      @editor.completions
    end

    # Rows the panel may grow to, border included.
    def max_rows=(rows : Int32) : Int32
      @max_rows = rows
      self.height = Layout::Sizing.fit max: rows
      rows
    end

    # ------------------------------------------------------------- events

    # Does whatever *key* is bound to and sends on whatever came of it.
    def press(key : Key) : Nil
      announce @editor.handle(key)
    end

    # Pasted text goes in as text. A field with no room for a line break
    # flattens them rather than dropping the rest.
    def paste(text : String) : Nil
      announce @editor.paste(text)
    end

    # Takes a key or a paste. Anything else is somebody else's.
    #
    # A key is claimed: nothing above a field should see what was typed into
    # it. A paste is not, because it is news about the terminal as much as it
    # is text: the field takes the text and whatever is showing a
    # `PasteNotice` still gets to hear that the paste is over.
    def handle(event : Event, context : Context) : Nil
      case event
      when Events::Key
        press event.key
        context.consume
      when Events::Paste
        paste event.text
      end
    end

    private def announce(outcome : Editor::Outcome) : Nil
      # The text changed, and how tall the field wants to be changes with it.
      invalidate_layout

      case outcome
      in .continue?  then nil
      in .accepted?  then emit Accepted.new(@editor.accepted)
      in .cancelled? then emit Cancelled.new
      in .ended?     then emit EndOfInput.new
      end
    end

    # `Tab` completes on a field that can complete, and moves focus on one that
    # cannot.
    #
    # A widget's own keymap is answered before the application's, so binding
    # the key here is what takes it back from the focus ring. A field with no
    # completion hook has nothing to do with it and leaves it alone, which is
    # what a form of plain fields wants.
    private def claim_completion_key : Nil
      unless @editor.completions
        self.keymap = nil
        return
      end

      self.keymap = Bindings.build do |map|
        map.bind COMPLETE, "complete the word", ->(_context : Context) { press COMPLETE; nil }
      end
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy
      wanted = prompt_width + Math.max(buffer.width, 1)

      Layout::Intrinsic.new prompt_width + 1, wanted
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy
      wanted = (@growth.fixed? ? 1 : rows_in(text_room(width)).size) + listing_rows

      Math.max wanted, 1
    end

    # Cells the prompt takes on the first row.
    def prompt_width : Int32
      prompt = @prompt
      prompt ? Unicode.string_width(prompt.text, @policy) : 0
    end

    private def continuation_width : Int32
      prompt = @prompt
      return 0 unless prompt

      continuation = prompt.continuation
      continuation ? Unicode.string_width(continuation, @policy) : prompt_width
    end

    # Cells left for text in a content box *width* across, which the prompt
    # eats into.
    #
    # The wider of the prompt and its continuation, so that a row is laid out
    # to fit under either and nothing overflows the one that is longer.
    private def text_room(width : Int32) : Int32
      Math.max width - Math.max(prompt_width, continuation_width), 0
    end

    # Cells left for text as the field was laid out.
    def text_width : Int32
      text_room content.width
    end

    # Where each row of text starts and ends, in cluster indices.
    def rows : Array(Range(Int32, Int32))
      rows_in text_width
    end

    # A fixed field is one row however long the text is. A growing one wraps at
    # the right edge and at every line break, and a cluster the terminal draws
    # double never straddles the edge: it moves down whole.
    private def rows_in(width : Int32) : Array(Range(Int32, Int32))
      return [0...buffer.size] if @growth.fixed?
      return [0...buffer.size] if width < 1

      wrap width
    end

    private def wrap(width : Int32) : Array(Range(Int32, Int32))
      lines = [] of Range(Int32, Int32)
      start = 0
      used = 0
      index = 0

      while index < buffer.size
        cluster = buffer[index] || ""

        if cluster == LineBuffer::NEWLINE
          lines << (start...index)
          index += 1
          start = index
          used = 0
          next
        end

        cells = buffer.width_at index

        if used + cells > width && index > start
          lines << (start...index)
          start = index
          used = 0
        end

        used += cells
        index += 1
      end

      lines << (start...buffer.size)
      # A cursor after a row that is exactly full belongs on the next row, and
      # that row has to exist for it to go there.
      lines << (buffer.size...buffer.size) if used == width
      lines
    end

    # Which row the cursor is on and how many cells into it.
    def cursor_cell : {Int32, Int32}
      cursor = buffer.cursor
      lines = rows

      lines.each_with_index do |range, index|
        # At a soft wrap the cursor belongs to the row it will type into, which
        # is the lower one, not the end of the row above.
        next if cursor >= range.end && index < lines.size - 1

        return {index, buffer.width_between range.begin, cursor}
      end

      last = lines.size - 1
      {last, buffer.width_between lines[last].begin, cursor}
    end

    # Rows of text the field would like, before the border and any listing.
    def text_rows : Int32
      @growth.fixed? ? 1 : rows.size
    end

    private def listing_rows : Int32
      case @editor.completion
      in .listing?            then @editor.candidates.size + 1
      in .choices?, .nothing? then 1
      in .idle?, .inserted?   then 0
      end
    end

    # Rows of text there is room to show, the listing taken off the bottom.
    def visible_rows : Int32
      Math.max content.height - listing_rows, 1
    end

    # Keeps the cursor in view, scrolling by the least that does it.
    #
    # Worked out at every draw rather than at every keystroke, because how much
    # is in view depends on the rectangle and the rectangle is the layout's to
    # change. Doing it on a keystroke measures against the panel as it was
    # before it grew.
    def reflow : Nil
      row, cell = cursor_cell
      width = text_width
      height = visible_rows

      if @growth.fixed?
        # A column is kept spare at each end for the markers, so that scrolling
        # into view does not put the cursor under one.
        room = Math.max width - 2, 1
        @offset = cell if cell < @offset
        @offset = cell - room if cell > @offset + room
        @offset = Math.max @offset, 0
      else
        @offset = row if row < @offset
        @offset = row - height + 1 if row >= @offset + height
        @offset = Math.max @offset, 0
      end
    end

    # Where the terminal's own cursor belongs, in the box the field draws in.
    def cursor_position : {Int32, Int32}?
      area = content
      return if area.empty?

      row, cell = cursor_cell
      right = Math.max area.width - 1, 0

      if @growth.fixed?
        {(prompt_width + cell - @offset).clamp(0, right), 0}
      else
        indent = row.zero? ? prompt_width : continuation_width
        {(indent + cell).clamp(0, right),
         (row - @offset).clamp(0, Math.max(area.height - 1, 0))}
      end
    end

    # ------------------------------------------------------------ drawing

    # Draws the prompt and as much of the text as there is room for.
    #
    # The ground and the box around it are the renderer's, from `Widget#style`
    # and `Widget#border`, and *view* is already cut to what they left.
    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      reflow
      area = view.bounds
      @growth.fixed? ? draw_fixed(view, area) : draw_wrapped(view, area)
      draw_listing view, area
    end

    private def draw_fixed(view : View, area : Rect) : Nil
      draw_prompt view, 0, first: true
      left = prompt_width
      width = Math.max area.width - left, 0
      return if width.zero?

      return draw_placeholder view, left, 0, width if buffer.empty?

      # A marker each side, so what is off the edge is visible rather than
      # merely absent.
      ahead = buffer.width - @offset > width
      behind = @offset > 0

      view.write_char left, 0, MARKERS[0], Style::DEFAULT.faint if behind
      inset = behind ? 1 : 0
      room = width - inset - (ahead ? 1 : 0)

      draw_clusters view, left + inset, 0, 0...buffer.size, @offset, room
      view.write_char left + width - 1, 0, MARKERS[1], Style::DEFAULT.faint if ahead
    end

    private def draw_wrapped(view : View, area : Rect) : Nil
      lines = rows
      height = visible_rows
      shown = 0

      (@offset...lines.size).each do |index|
        break if shown >= height || shown >= area.height

        first = index.zero?
        draw_prompt view, shown, first
        indent = first ? prompt_width : continuation_width

        if buffer.empty? && first
          draw_placeholder view, indent, shown, area.width - indent
        else
          draw_clusters view, indent, shown, lines[index], 0,
            Math.max(area.width - indent, 0)
        end

        shown += 1
      end
    end

    private def draw_prompt(view : View, y : Int32, first : Bool) : Nil
      prompt = @prompt
      return unless prompt

      if first
        view.write 0, y, prompt.text, prompt.style
        return
      end

      continuation = prompt.continuation
      return unless continuation

      view.write 0, y, continuation, prompt.style
    end

    private def draw_placeholder(view : View, x : Int32, y : Int32, room : Int32) : Nil
      text = @placeholder
      return unless text && room > 0

      view.write x, y, text, @placeholder_style
    end

    # Writes *range* starting at (*x*, *y*), skipping *skip* cells of it and
    # stopping after *room*. Clusters are gathered into runs of one style, so a
    # line with nothing selected costs one write rather than one per character.
    #
    # A cluster straddling either edge is left out rather than halved: there is
    # no half of a wide character to draw.
    private def draw_clusters(view : View, x : Int32, y : Int32,
                              range : Range(Int32, Int32), skip : Int32, room : Int32) : Nil
      return if room <= 0

      selection = buffer.selection
      column = 0
      run = String::Builder.new
      run_style = Style::DEFAULT
      run_x = x

      range.each do |index|
        cells = buffer.width_at index
        start = column
        column += cells
        next if start < skip
        break if column - skip > room

        style = selection && selection.includes?(index) ? @selection_style : Style::DEFAULT
        at = x + start - skip

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

    private def draw_listing(view : View, area : Rect) : Nil
      top = visible_rows
      room = area.height - top
      return if room <= 0

      # A completion that changed nothing has to say so, or a key that found
      # no match and a key that is not bound look exactly alike.
      case @editor.completion
      in .nothing?          then view.write 1, top, "no match", Style::DEFAULT.faint
      in .choices?          then view.write 1, top, choices_note, Style::DEFAULT.faint
      in .listing?          then draw_candidates view, top, room
      in .idle?, .inserted? then return
      end
    end

    private def choices_note : String
      "#{@editor.candidates.size} matches, again to list"
    end

    private def draw_candidates(view : View, top : Int32, room : Int32) : Nil
      candidates = @editor.candidates
      shown = Math.min candidates.size, room - 1

      shown.times do |index|
        view.write 1, top + index, candidates[index], Style::DEFAULT.faint
      end

      left = candidates.size - shown
      note = left.zero? ? "#{candidates.size} candidates" : "#{left} more"
      view.write 1, top + shown, note, Style::DEFAULT.faint if room > shown
    end
  end
end
