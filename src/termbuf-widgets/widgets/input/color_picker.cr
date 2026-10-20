require "../../message"
require "../../router"
require "../../widget"
require "../depth"
require "../display/color_swatch"
require "../field"
require "../panel"
require "./interactive"

module TermBuf::Widgets
  # Somewhere to choose a color, from a grid or by its value.
  #
  #     picker = ColorPicker.new Color.rgb(0x3080C0), depth: Depth::TrueColor
  #     picker.reset_to = Color.rgb(0xC0C0C0)
  #     root.add picker
  #
  # From the top, the picker is a `ColorSwatch` showing the current color, a
  # grid of colors, a row of fields for red, green and blue, and a field for
  # the hex value.
  #
  # ### The grid
  #
  # The grid is the 256 color palette's 6 by 6 by 6 cube, drawn as six blocks
  # of 6 by 6 side by side, with the 24 greys in a row under it. Each block is
  # one level of red, its rows are green and its columns blue. At
  # `Depth::Indexed256` the 16 system colors sit in a row above the cube, and
  # every cell is an `Indexed` color. At `Depth::TrueColor` the same cells are
  # the `Rgb` colors the palette defines.
  #
  # A cell is two columns wide, so it comes out square, and the grid is 72
  # columns across. Given fewer than 72 the cells are one column wide, and
  # given fewer than 36 the grid is not drawn and takes no rows. A grid cut
  # short by a short screen is not drawn either, so the swatch and the fields
  # still work in three rows. The arrows move a cursor over the grid, and
  # `Enter`, `Space` or a click takes the color under it.
  #
  # `#reset_to` adds a "default" cell at the end of the grey row. Taking it
  # sets the value to that color.
  #
  # ### The fields
  #
  # Each channel field takes a number from 0 to 255. `Up` and `Right` step it
  # up, `Down` and `Left` step it down, and `Home` and `End` go to 0 and 255.
  # `Enter` clamps what was typed. The hex field takes `#rrggbb` or `rrggbb`.
  # Typing in any field moves the value as soon as the text is a whole color,
  # and the swatch, the grid's cursor and the other fields follow.
  #
  # At `Depth::Indexed256` the value is always a palette index. A field edit
  # takes the nearest index at once, and the fields show that index's own
  # channels once the field is left with `Tab`, `Enter` or a click elsewhere
  # in the picker. A step goes on to the next index along that channel.
  #
  # ### Keys
  #
  # `Tab` and `Shift+Tab` move between the grid and the four fields, and wrap
  # at either end. The arrows move within the grid or step a field.
  #
  # ### What it says
  #
  # `Changed` carries the color, and is sent for every change the user makes.
  # Whether a change is final is the application's to decide, so a picker in
  # a popover can apply each one as it comes and a picker in a dialog can wait
  # for OK. `#value=` sends nothing.
  class ColorPicker < Widget
    # The value changed.
    struct Changed < Message
      # Which picker it was.
      getter picker : ColorPicker

      # The color it now holds.
      getter color : Color

      def initialize(@picker : ColorPicker, @color : Color)
      end
    end

    # A field that refuses text its rule turns down, and says when its text
    # changed.
    #
    # The change goes to a proc and not a message, because the picker has to
    # follow the text while it is typed, and a message arrives a pump late.
    class Entry < Field
      # Called after any key or paste that changed the text.
      property on_change : Proc(Nil)? = nil

      # Whether the field may hold a text.
      getter rule : Proc(String, Bool)

      # A fixed field keeps a column spare at each end for its scroll markers,
      # so *cells* of text need two more than the prompt and the text.
      def initialize(prompt : String, cells : Int32, @rule : Proc(String, Bool))
        super prompt: Field::Prompt.new(prompt)
        self.width = Layout::Sizing.fixed prompt.size + cells + 2
        self.height = Layout::Sizing.fixed 1
      end

      # Takes the key the way a field does. Text the rule refuses is put back
      # the way it was.
      def press(key : Key) : Nil
        before = text
        super
        changed before
      end

      # :ditto:
      def paste(text : String) : Nil
        before = self.text
        super
        changed before
      end

      private def changed(before : String) : Nil
        return if text == before
        return restore before unless @rule.call text

        @on_change.try &.call
      end

      private def restore(before : String) : Nil
        self.text = before
      end
    end

    # A field holding one integer in a range, stepped with the arrows.
    #
    # It has the surface `NumberField` is to have, so the picker can take
    # that instead with a change of type. `#on_change` is the one addition.
    # The picker follows the text as it is typed, and `Changed` is sent only
    # for a step and for `Enter`.
    class ChannelField < Field
      # The value was stepped or accepted.
      struct Changed < Message
        # Which field it was.
        getter field : ChannelField

        # The value it now holds.
        getter value : Int32

        def initialize(@field : ChannelField, @value : Int32)
        end
      end

      # The values the field may hold.
      getter range : Range(Int32, Int32)

      # How far one press of an arrow moves the value.
      getter step : Int32

      # Called after any key or paste that changed the text.
      property on_change : Proc(Nil)? = nil

      @value : Int32

      def initialize(value : Int32 = 0, @range : Range(Int32, Int32) = 0..255,
                     @step : Int32 = 1, prompt : String = "")
        super prompt: Field::Prompt.new(prompt)
        @value = value.clamp @range
        self.text = @value.to_s

        # A fixed field keeps a column spare at each end for its scroll
        # markers.
        digits = {@range.begin.to_s.size, @range.end.to_s.size}.max
        self.width = Layout::Sizing.fixed prompt.size + digits + 2
        self.height = Layout::Sizing.fixed 1
        self.keymap = stepping
      end

      # The value, as last set, stepped or accepted.
      def value : Int32
        @value
      end

      # Sets the value without saying so, held to `#range`.
      def value=(value : Int32) : Int32
        @value = value.clamp @range
        self.text = @value.to_s unless text == @value.to_s
        @value
      end

      # What the text says, or `nil` when it is not a number in `#range`.
      def typed : Int32?
        number = text.to_i?
        number if number && @range.includes?(number)
      end

      # Moves the value *steps* steps from what is typed, held to `#range`,
      # and says so.
      def step_by(steps : Int32) : Nil
        go_to (typed || @value) + steps * @step
      end

      # Sets the value to *value*, held to `#range`, and says so.
      def go_to(value : Int32) : Nil
        self.value = value
        emit Changed.new(self, @value)
      end

      # Takes what is typed, clamped to `#range`, and says so. Text that is
      # not a number is put back to the value.
      def accept : Nil
        go_to text.to_i? || @value
      end

      # Takes the key the way a field does. A key that leaves anything but
      # digits is undone.
      def press(key : Key) : Nil
        before = text
        super
        changed before
      end

      # :ditto:
      def paste(text : String) : Nil
        before = self.text
        super
        changed before
      end

      private def changed(before : String) : Nil
        return if text == before
        return self.text = before unless text.each_char.all?(&.ascii_number?)

        @on_change.try &.call
      end

      private def stepping : Bindings
        Bindings.build do |map|
          map.bind Key.parse("Up"), "step up", ->(_context : Context) { step_by 1 }
          map.bind Key.parse("Right"), "step up", ->(_context : Context) { step_by 1 }
          map.bind Key.parse("Down"), "step down", ->(_context : Context) { step_by(-1) }
          map.bind Key.parse("Left"), "step down", ->(_context : Context) { step_by(-1) }
          map.bind Key.parse("Home"), "the least value",
            ->(_context : Context) { go_to @range.begin }
          map.bind Key.parse("End"), "the greatest value",
            ->(_context : Context) { go_to @range.end }
          map.bind Key.parse("Enter"), "take what is typed", ->(_context : Context) { accept }
        end
      end
    end

    # The colors to pick from, and a cursor over them.
    class Grid < Widget
      include Interactive

      # One place on the grid. *column* and *span* are in cells, and a cell
      # with a *label* draws it over the color.
      record Cell, color : Color, column : Int32, span : Int32 = 1, label : String? = nil

      # Cells across the widest row.
      COLUMNS = 36

      # The cell the "default" entry starts at, on the grey row.
      RESET_COLUMN = 25

      # What the "default" entry says.
      RESET_LABEL = "default"

      # The rows of cells, top first.
      getter rows = [] of Array(Cell)

      # Which row the cursor is on.
      getter row : Int32 = 0

      # Which cell of that row the cursor is on.
      getter entry : Int32 = 0

      # The depth the cells were built for.
      getter depth : Depth = Depth::TrueColor

      # Called with the color under the cursor when it is taken.
      property on_take : Proc(Color, Nil)? = nil

      # Whether a layout has measured the grid yet.
      @measured = false

      def initialize(depth : Depth, reset_to : Color?)
        @width = Layout::Sizing.fit
        @height = Layout::Sizing.fit
        build depth, reset_to
        self.keymap = moving
      end

      # Builds the cells again for *depth*, with a "default" cell for
      # *reset_to* when there is one. The cursor keeps its place where it
      # can.
      def build(depth : Depth, reset_to : Color?) : Nil
        @depth = depth
        @rows = Grid.rows_for depth, reset_to
        @row = @row.clamp 0, @rows.size - 1
        @entry = @entry.clamp 0, @rows[@row].size - 1
        invalidate_layout
      end

      # The cells of a grid at *depth*.
      def self.rows_for(depth : Depth, reset_to : Color?) : Array(Array(Cell))
        indexed = depth.indexed256?
        rows = [] of Array(Cell)
        rows << (0...16).map { |index| Cell.new Color.indexed(index), index } if indexed

        6.times do |green|
          rows << (0...COLUMNS).map do |column|
            Cell.new palette(16 + (column // 6) * 36 + green * 6 + column % 6, indexed), column
          end
        end

        greys = (0...24).map { |step| Cell.new palette(232 + step, indexed), step }
        if color = reset_to
          greys << Cell.new(color, RESET_COLUMN, COLUMNS - RESET_COLUMN, RESET_LABEL)
        end
        rows << greys
      end

      private def self.palette(index : Int32, indexed : Bool) : Color
        color = Color.indexed index
        return color if indexed

        red, green, blue = color.channels
        Color.rgb red, green, blue
      end

      # The cell under the cursor.
      def current : Cell
        @rows[@row][@entry]
      end

      # Moves the cursor *across* cells along its row and *down* rows,
      # stopping at the edges. Moving between rows keeps the column where the
      # other row has a cell there.
      def move(across : Int32, down : Int32) : Nil
        unless across.zero?
          @entry = (@entry + across).clamp 0, @rows[@row].size - 1
        end
        return if down.zero?

        column = current.column
        @row = (@row + down).clamp 0, @rows.size - 1
        @entry = nearest @rows[@row], column
      end

      # Puts the cursor on the cell holding *color*, and leaves it where it
      # is when no cell does. The "default" cell is the last choice.
      def point_at(color : Color) : Nil
        found = place_of(color) { |cell| cell.label.nil? } || place_of(color, &.label)
        @row, @entry = found if found
      end

      private def place_of(color : Color, & : Cell -> _) : {Int32, Int32}?
        @rows.each_with_index do |cells, row|
          cells.each_with_index do |cell, entry|
            return {row, entry} if cell.color == color && yield cell
          end
        end
        nil
      end

      private def nearest(cells : Array(Cell), column : Int32) : Int32
        cells.index { |cell| cell.column <= column < cell.column + cell.span } ||
          cells.rindex { |cell| cell.column <= column } || 0
      end

      # Takes the color under the cursor.
      def take : Nil
        @on_take.try &.call(current.color)
      end

      # Whether the grid has room to be drawn: the columns of one-column
      # cells and every row.
      def shown? : Bool
        area = content
        area.width >= COLUMNS && area.height >= @rows.size
      end

      # Focus lands here when the grid is on the screen, and before the first
      # layout, so the grid is where the keyboard starts.
      def focusable? : Bool
        !@measured || shown?
      end

      # Columns per cell in a grid *width* columns wide.
      def cell_width(width : Int32) : Int32
        width >= COLUMNS * 2 ? 2 : 1
      end

      # Takes a click on a cell.
      def handle(event : Event, context : Context) : Nil
        return unless event.is_a? Events::Mouse

        clicked event, context do
          if aim event.x, event.y
            take_focus context
            take
          end
        end
      end

      # Puts the cursor on the cell at (*x*, *y*) in buffer coordinates,
      # answering whether there was one there.
      private def aim(x : Int32, y : Int32) : Bool
        area = content
        row = y - area.y
        return false unless shown? && 0 <= row < @rows.size

        column = (x - area.x) // cell_width(area.width)
        entry = @rows[row].index { |cell| cell.column <= column < cell.column + cell.span }
        return false unless entry

        @row = row
        @entry = entry
        true
      end

      private def moving : Bindings
        Bindings.build do |map|
          map.bind Key.parse("Left"), "the color to the left",
            ->(_context : Context) { move(-1, 0) }
          map.bind Key.parse("Right"), "the color to the right",
            ->(_context : Context) { move 1, 0 }
          map.bind Key.parse("Up"), "the color above", ->(_context : Context) { move 0, -1 }
          map.bind Key.parse("Down"), "the color below", ->(_context : Context) { move 0, 1 }
          map.bind Key.parse("Enter"), "take this color", ->(_context : Context) { take }
          map.bind Key.parse("Space"), "take this color", ->(_context : Context) { take }
        end
      end

      # ----------------------------------------------------------- layout

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        Layout::Intrinsic.new COLUMNS, COLUMNS * 2
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        @measured = true
        width >= COLUMNS ? @rows.size : 0
      end

      # ---------------------------------------------------------- drawing

      def draw(view : View) : Nil
        return unless view.width >= COLUMNS && view.height >= @rows.size

        wide = cell_width view.width
        @rows.each_with_index do |cells, row|
          cells.each { |cell| draw_cell view, cell, row, wide }
        end
        draw_cursor view, wide if focused?
      end

      private def draw_cell(view : View, cell : Cell, y : Int32, wide : Int32) : Nil
        x = cell.column * wide
        cells = cell.span * wide
        view.fill Rect.new(x, y, cells, 1), ' ', Style::DEFAULT.bg(cell.color)

        label = cell.label
        return unless label && label.size <= cells

        view.write x + (cells - label.size) // 2, y, label, ink_on(cell.color)
      end

      private def draw_cursor(view : View, wide : Int32) : Nil
        cell = current
        x = cell.column * wide
        cells = cell.span * wide
        style = ink_on cell.color

        if cells >= 2
          view.write x, @row, "[", style
          view.write x + cells - 1, @row, "]", style
        else
          view.write x, @row, Glyphs.choose({"◆"}, {"*"}, view.policy).first, style
        end
      end

      private def ink_on(color : Color) : Style
        Style::DEFAULT.fg(@depth.ink(color)).bg(color)
      end
    end

    # What the hex field may hold: an optional `#` and up to six hex digits.
    HEX = ->(text : String) { text.matches? /\A#?[0-9a-fA-F]{0,6}\z/ }

    # The swatch at the top.
    getter swatch : ColorSwatch

    # The grid of colors.
    getter grid : Grid

    # The red field.
    getter red : ChannelField

    # The green field.
    getter green : ChannelField

    # The blue field.
    getter blue : ChannelField

    # The row the three channel fields sit in.
    getter channels : Panel

    # The hex field.
    getter hex : Entry

    # How many colors are offered.
    getter depth : Depth

    # The color the "default" cell takes, or `nil` for no such cell.
    getter reset_to : Color?

    @value : Color
    @editing : Field? = nil

    def initialize(color : Color,
                   depth : Depth = Depth::TrueColor,
                   reset_to : Color? = nil,
                   style : Style? = nil)
      @depth = depth
      @reset_to = reset_to
      @value = depth.shown color
      @style = style
      @direction = Layout::Direction::Column
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fit

      @swatch = ColorSwatch.new @value, depth: depth
      @grid = Grid.new depth, reset_to
      @red = ChannelField.new prompt: "R "
      @green = ChannelField.new prompt: "G "
      @blue = ChannelField.new prompt: "B "
      @hex = Entry.new "Hex ", 7, HEX
      @channels = Panel.new direction: Layout::Direction::Row,
        height: Layout::Sizing.fixed(1), gap: 2
      @channels.add @red, @green, @blue

      add @swatch, @grid, @channels, @hex
      wire
      show_value nil
      self.keymap = tabbing
    end

    # The color chosen.
    def value : Color
      @value
    end

    # Sets the color without saying so. At `Depth::Indexed256` it becomes the
    # nearest palette index.
    def value=(color : Color) : Color
      @value = @depth.shown color
      @editing = nil
      show_value nil
      @value
    end

    # Offers *depth* instead. The grid is built again and the value moves to
    # what that depth can show, without a `Changed`.
    def depth=(depth : Depth) : Depth
      return depth if depth == @depth

      @depth = depth
      @swatch.depth = depth
      @grid.build depth, @reset_to
      self.value = @value
      depth
    end

    # Adds a "default" cell taking *color*, or takes it away for `nil`.
    def reset_to=(color : Color?) : Color?
      @reset_to = color
      @grid.build @depth, color
      @grid.point_at @value
      color
    end

    # Writes every field again from the value, which is what leaving a field
    # does. At `Depth::Indexed256` this is where the channel fields come to
    # show the index's own channels.
    def settle : Nil
      return unless @editing

      @editing = nil
      show_value nil
    end

    # The places `Tab` moves between, in order. The grid is left out while it
    # is not drawn.
    def stops : Array(Widget)
      found = [] of Widget
      found << @grid if @grid.focusable?
      found << @red << @green << @blue << @hex
    end

    # Moves the keyboard *step* places along `#stops`, wrapping at either end,
    # and settles the field it leaves.
    def step_stop(context : Context, step : Int32) : Nil
      settle
      parts = stops
      held = context.focus.current
      at = held ? parts.index(&.same?(held)) : nil
      at ||= step > 0 ? -1 : 0

      context.focus.focus parts[(at + step) % parts.size]
    end

    # Claims what the fields say, and takes a click on a field.
    def handle(event : Event, context : Context) : Nil
      case event
      when ChannelField::Changed
        context.consume
        channel_moved event.field, event.value
      when Field::Accepted, Field::Cancelled, Field::EndOfInput
        context.consume
      when Events::Mouse
        click_field event, context
      end
    end

    private def click_field(event : Events::Mouse, context : Context) : Nil
      return unless event.button.left? && event.action.press?

      field = {@red, @green, @blue, @hex}.find &.frame.contains?(event.x, event.y)
      return unless field

      settle unless field.same? @editing
      context.focus.focus field
      context.consume
    end

    # ------------------------------------------------------------- editing

    private def wire : Nil
      @grid.on_take = ->(color : Color) { take color; nil }

      {@red, @green, @blue}.each do |field|
        field.on_change = -> { channel_edited field; nil }
      end
      @hex.on_change = -> { hex_edited; nil }
      @hex.keymap = Bindings.build do |map|
        map.bind Key.parse("Enter"), "settle the value", ->(_context : Context) { settle }
      end
    end

    private def take(color : Color) : Nil
      settle
      change color, nil
    end

    private def channel_edited(field : ChannelField) : Nil
      @editing = field
      levels = typed_channels
      change Color.rgb(*levels), field if levels
    end

    private def hex_edited : Nil
      @editing = @hex
      digits = @hex.text.lchop '#'
      change Color.rgb(digits.to_i(16)), @hex if digits.size == 6
    end

    # The three channel fields as numbers, or `nil` while one is not a
    # channel.
    private def typed_channels : {Int32, Int32, Int32}?
      red = @red.typed
      green = @green.typed
      blue = @blue.typed
      {red, green, blue} if red && green && blue
    end

    # Answers a step or an `Enter` in the channel *field*, which now holds
    # *level*.
    #
    # At `Depth::Indexed256` a step of one usually lands on the same index.
    # A step that does, in a field with nothing typed in it, goes on along
    # the palette's cube levels in the same direction until the index moves.
    # After typing, a step or an `Enter` takes the nearest index and settles.
    private def channel_moved(field : ChannelField, level : Int32) : Nil
      which = {@red, @green, @blue}.index!(&.same?(field))
      levels = @value.channels.to_a
      before = levels[which]
      typing = field.same? @editing
      levels[which] = level
      candidate = @depth.shown Color.rgb(levels[0], levels[1], levels[2])

      if candidate == @value && !typing && level != before
        candidate = walk(levels, which, before, level <=> before) || candidate
      end

      @editing = nil
      return show_value nil if candidate == @value

      change candidate, nil
    end

    # The first color along the channel *which* from *level*, in *direction*,
    # that is not the value, or `nil` when the channel runs out first.
    private def walk(levels : Array(Int32), which : Int32, level : Int32,
                     direction : Int32) : Color?
      levels_from(level, direction).each do |next_level|
        levels[which] = next_level
        candidate = @depth.shown Color.rgb(levels[0], levels[1], levels[2])
        return candidate unless candidate == @value
      end
      nil
    end

    # The palette's cube levels past *level* in *direction*, nearest first.
    private def levels_from(level : Int32, direction : Int32) : Array(Int32)
      cube = Color::CUBE_LEVELS.to_a
      direction > 0 ? cube.select(&.> level) : cube.select(&.< level).reverse!
    end

    # Moves the value to *color* and says so, unless it is already there.
    # *editing* is the field being typed in, which is left as typed.
    private def change(color : Color, editing : Field?) : Nil
      color = @depth.shown color
      return if color == @value

      @value = color
      show_value editing
      emit Changed.new(self, @value)
    end

    # Puts the value in the swatch, the grid's cursor and the fields.
    #
    # The field being typed in keeps its text. At `Depth::Indexed256` a
    # channel field being typed in keeps all three channel fields as typed,
    # since the index's channels would overwrite the other two.
    private def show_value(editing : Field?) : Nil
      @swatch.color = @value
      @grid.point_at @value

      typing_channel = !editing.nil? && !editing.same?(@hex)
      keep_channels = typing_channel && @depth.indexed256?
      levels = @value.channels

      {@red, @green, @blue}.each_with_index do |field, which|
        next if keep_channels || field.same?(editing)

        field.value = levels[which]
      end
      put @hex, Depth.hex(@value) unless @hex.same?(editing)
    end

    private def put(field : Entry, text : String) : Nil
      field.text = text unless field.text == text
    end

    private def tabbing : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Tab"), "the next part", ->(context : Context) { step_stop context, 1 }
        map.bind Key.parse("Shift+Tab"), "the part before",
          ->(context : Context) { step_stop context, -1 }
      end
    end
  end
end
