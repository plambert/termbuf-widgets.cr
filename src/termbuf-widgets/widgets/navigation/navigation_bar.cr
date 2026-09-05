require "../../message"
require "../../router"
require "../../widget"
require "../input/interactive"

module TermBuf::Widgets
  # A row of places to go, one of them highlighted.
  #
  #     bar = NavigationBar.new brand: "termbuf"
  #     bar.add "files", hint: "F1"
  #     bar.add "edit", hint: "F2"
  #     bar.trailing = "12:04"
  #
  # The arrows that run along the bar move the highlight, `Enter` activates
  # what is highlighted, and a click activates what was clicked. Either way the
  # bar emits `Selected`, and then whatever the item carries: the `Message` it
  # was given, and the `Proc` it was given.
  #
  # ### Why it draws its own items
  #
  # A bar too narrow for its items gives up the labels before it gives up the
  # items, and that is a decision about the whole row rather than about any one
  # item in it: the layout engine apportions space between children without
  # ever asking a child to spell itself differently. So the bar is a leaf. It
  # measures the three spellings of the row — the hints with the labels, the
  # hints alone, and one mark per item — and draws the widest that fits, giving
  # up the trailing slot and then the brand rather than cutting an item in
  # half.
  class NavigationBar < Widget
    include Interactive

    # An item was activated.
    struct Selected < Message
      # The bar it happened on, since one handler usually answers several.
      getter bar : NavigationBar

      # Which item it was, counting from zero.
      getter index : Int32

      # The item itself.
      getter item : Item

      def initialize(@bar : NavigationBar, @index : Int32, @item : Item)
      end
    end

    # One place to go.
    #
    # An item says what it is and, optionally, what activating it means: a
    # `Message` for an application that answers messages in `Widget#handle`,
    # and a `Proc` for one that would rather write the answer beside the item.
    # Both are sent when both are given.
    class Item
      # What the item says.
      property label : String

      # The short spelling — a key name, usually — shown in front of the label
      # and left standing alone when the bar runs out of room for labels.
      property hint : String?

      # Emitted when the item is activated, after `Selected`.
      property message : Message?

      # Run when the item is activated, after the messages.
      property action : Proc(Nil)?

      def initialize(@label : String, @hint : String? = nil,
                     @message : Message? = nil, @action : Proc(Nil)? = nil)
      end

      # The widest spelling: the hint and the label together.
      def full : String
        hint = @hint
        hint ? "#{hint} #{@label}" : @label
      end

      # The narrow spelling: the hint on its own, or the label when there is
      # no hint to fall back to.
      def short : String
        @hint || @label
      end
    end

    # How much of an item is spelled out.
    enum Detail
      # The hint and the label.
      Full

      # The hint alone.
      Short

      # One mark per item, which is as narrow as a bar goes.
      Marks
    end

    # What the row comes out as at a given width.
    record Fit, detail : Detail, brand : Bool, trailing : Bool do
      # Whether the brand is drawn.
      def brand? : Bool
        @brand
      end

      # Whether the trailing slot is drawn.
      def trailing? : Bool
        @trailing
      end
    end

    # Where one item was drawn, in buffer coordinates, so that a click can be
    # turned back into an item.
    record Span, index : Int32, x : Int32, y : Int32, width : Int32 do
      # Whether (*x*, *y*) falls on this item.
      def holds?(x : Int32, y : Int32) : Bool
        y == @y && @x <= x < @x + @width
      end
    end

    # The mark an item collapses to on a terminal that measures it at one cell.
    ELLIPSIS = "…"

    # What stands in for it where it does not come out at one cell.
    ELLIPSIS_ASCII = "."

    # Written before the items, or `nil` for a bar with no brand.
    layout_property brand : String? = nil

    # Written at the far end of the row, or `nil` for none. The first thing
    # given up when the row is too narrow.
    layout_property trailing : String? = nil

    # Cells of space either side of an item's text.
    layout_property item_padding : Int32 = 1

    # What an item that is not highlighted is drawn in.
    property item_style : Style = Style::DEFAULT

    # What the highlighted item is drawn in while the bar has the keyboard.
    property focused_style : Style = Style::DEFAULT.reverse

    # What it is drawn in while the bar does not.
    property selected_style : Style = Style::DEFAULT.bold

    # What the brand is drawn in.
    property brand_style : Style = Style::DEFAULT.bold

    # What the trailing slot is drawn in.
    property trailing_style : Style = Style::DEFAULT.faint

    # The items, in the order they were added.
    getter items = [] of Item

    # Which item is highlighted, counting from zero.
    getter selected : Int32 = 0

    @spans = [] of Span

    def initialize(brand : String? = nil,
                   trailing : String? = nil,
                   direction : Layout::Direction = Layout::Direction::Row,
                   style : Style? = nil)
      @brand = brand
      @trailing = trailing
      @direction = direction
      @style = style
      resize
      rebind
    end

    # ------------------------------------------------------------- items

    # Adds an item and answers it.
    def add(label : String, hint : String? = nil, message : Message? = nil,
            action : Proc(Nil)? = nil) : Item
      item = Item.new label, hint, message, action
      add item
      item
    end

    # Adds *item* and answers it.
    def add(item : Item) : Item
      @items << item
      invalidate_layout
      item
    end

    # Takes the item at *index* out, answering it, or `nil` when there was
    # none there.
    def remove_at(index : Int32) : Item?
      return unless 0 <= index < @items.size

      item = @items.delete_at index
      self.selected = @selected
      invalidate_layout
      item
    end

    # Highlights the item at *index*, held inside the items there are.
    #
    # Setting the highlight says nothing: a message is what the user did, and
    # this is the application saying where things stand.
    def selected=(index : Int32) : Int32
      @selected = index.clamp 0, Math.max(@items.size - 1, 0)
    end

    # The highlighted item, or `nil` on an empty bar.
    def selected_item : Item?
      @items[@selected]?
    end

    # --------------------------------------------------------- activating

    # Moves the highlight *step* places, wrapping at either end.
    def step(step : Int32) : Nil
      return if @items.empty?

      @selected = (@selected + step) % @items.size
    end

    # Activates the item at *index*: says `Selected`, then whatever the item
    # itself carries. Does nothing for an index nothing answers to.
    def activate(index : Int32) : Nil
      item = @items[index]?
      return unless item

      self.selected = index
      emit Selected.new self, index, item
      item.message.try { |message| emit message }
      item.action.try &.call
    end

    # Activates whatever is highlighted.
    def activate : Nil
      activate @selected
    end

    # -------------------------------------------------------------- input

    # Focus lands on the bar itself, which is the one thing that moves the
    # highlight; the items are drawn rather than built, so there is nothing
    # under it for focus to land on instead.
    def focusable? : Bool
      true
    end

    # The item drawn at (*x*, *y*) in buffer coordinates, as the last frame
    # drew it, or `nil` when the point is not on one.
    def item_at(x : Int32, y : Int32) : Int32?
      @spans.find(&.holds?(x, y)).try &.index
    end

    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      clicked event, context do
        take_focus context
        index = item_at event.x, event.y
        activate index if index
      end
    end

    # Which way the arrows run: along the bar.
    def direction=(value : Layout::Direction) : Layout::Direction
      result = super
      resize
      rebind
      result
    end

    private def rebind : Nil
      back, on = case @direction
                 in .row?    then {"Left", "Right"}
                 in .column? then {"Up", "Down"}
                 end

      self.keymap = Bindings.build do |map|
        map.bind Key.parse(back), "the item before",
          ->(_context : Context) { step(-1); nil }
        map.bind Key.parse(on), "the item after",
          ->(_context : Context) { step 1; nil }
        map.bind Key.parse("Enter"), "go where this item goes",
          ->(_context : Context) { activate; nil }
      end
    end

    # A bar runs the length of what it is in and is as thick as its content.
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

    # ------------------------------------------------------------ measuring

    # The mark an item collapses to under *policy*.
    def mark(policy : Unicode::WidthPolicy) : String
      Glyphs.single_cell?({ELLIPSIS}, policy) ? ELLIPSIS : ELLIPSIS_ASCII
    end

    # What the item at *index* reads as when the row is drawn at *detail*.
    def text_of(item : Item, detail : Detail, policy : Unicode::WidthPolicy) : String
      case detail
      in .full?  then item.full
      in .short? then item.short
      in .marks? then mark policy
      end
    end

    # How the row comes out at *width*: the detail its items are drawn at, and
    # which of the brand and the trailing slot there is room for.
    #
    # Spelling the items out matters more than the two things around them, so
    # each detail is tried with everything, then without the trailing slot,
    # then without the brand either, before the next detail down is considered
    # at all. What the bar is for is the items.
    def fit_for(width : Int32, policy : Unicode::WidthPolicy) : Fit
      branded = brand_width policy
      trailed = trailing_width policy

      Detail.values.each do |detail|
        room = items_width detail, policy

        return Fit.new detail, true, true if branded + room + trailed <= width
        return Fit.new detail, true, false if branded + room <= width
        return Fit.new detail, false, false if room <= width
      end

      Fit.new Detail::Marks, false, false
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      case @direction
      in .row?    then row_intrinsic policy
      in .column? then column_intrinsic policy
      end
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      case @direction
      in .row?    then 1
      in .column? then rows
      end
    end

    # How many rows a bar running downwards takes.
    private def rows : Int32
      count = @items.size
      count += 1 if @brand
      count += 1 if @trailing
      count
    end

    private def row_intrinsic(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      wanted = brand_width(policy) + items_width(Detail::Full, policy) + trailing_width(policy)
      Layout::Intrinsic.new items_width(Detail::Marks, policy), wanted
    end

    private def column_intrinsic(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      widest = 0
      narrowest = 0

      @items.each do |item|
        widest = Math.max widest, cell_width(item.full, policy)
        narrowest = Math.max narrowest, cell_width(item.short, policy)
      end

      # The brand and the trailing slot get a row each and are cut to fit, so
      # they say what the bar would rather be without saying what it needs.
      {@brand, @trailing}.each do |text|
        widest = Math.max widest, cell_width(text, policy) if text
      end

      Layout::Intrinsic.new Math.min(narrowest, widest), widest
    end

    # How wide a cell holding *text* comes out, its padding included.
    private def cell_width(text : String, policy : Unicode::WidthPolicy) : Int32
      Unicode.string_width(text, policy) + 2 * @item_padding
    end

    private def items_width(detail : Detail, policy : Unicode::WidthPolicy) : Int32
      @items.sum { |item| cell_width text_of(item, detail, policy), policy }
    end

    private def brand_width(policy : Unicode::WidthPolicy) : Int32
      text = @brand
      text ? cell_width(text, policy) : 0
    end

    private def trailing_width(policy : Unicode::WidthPolicy) : Int32
      text = @trailing
      text ? cell_width(text, policy) : 0
    end

    # ------------------------------------------------------------- drawing

    def draw(view : View) : Nil
      @spans.clear
      return if view.width <= 0 || view.height <= 0

      case @direction
      in .row?    then draw_row view
      in .column? then draw_column view
      end
    end

    private def draw_row(view : View) : Nil
      fit = fit_for view.width, view.policy
      column = 0

      if fit.brand? && (brand = @brand)
        column += draw_cell view, column, 0, brand, @brand_style
      end

      @items.each_with_index do |item, index|
        text = text_of item, fit.detail, view.policy
        width = draw_cell view, column, 0, text, style_for(index)
        remember index, column, 0, width
        column += width
      end

      draw_trailing view, fit, column
    end

    private def draw_trailing(view : View, fit : Fit, column : Int32) : Nil
      text = @trailing
      return unless fit.trailing? && text

      room = cell_width text, view.policy
      draw_cell view, Math.max(column, view.width - room), 0, text, @trailing_style
    end

    private def draw_column(view : View) : Nil
      row = 0

      if brand = @brand
        draw_cell view, 0, row, brand, @brand_style
        row += 1
      end

      @items.each_with_index do |item, index|
        break if row >= view.height

        width = draw_cell view, 0, row, item.full, style_for(index)
        remember index, 0, row, width
        row += 1
      end

      trailing = @trailing
      draw_cell view, 0, row, trailing, @trailing_style if trailing && row < view.height
    end

    # Writes one cell and answers how many columns it took.
    private def draw_cell(view : View, column : Int32, row : Int32, text : String,
                          paint : Style) : Int32
      pad = " " * @item_padding
      room = Math.max view.width - column, 0
      shown = Unicode.ellipsize "#{pad}#{text}#{pad}", room, mark(view.policy), view.policy
      view.write column, row, shown, paint
      Unicode.string_width shown, view.policy
    end

    # Where an item ended up, in buffer coordinates.
    private def remember(index : Int32, column : Int32, row : Int32, width : Int32) : Nil
      box = content
      @spans << Span.new(index, box.x + column, box.y + row, width)
    end

    private def style_for(index : Int32) : Style
      return @item_style unless index == @selected

      focused? ? @focused_style : @selected_style
    end
  end
end
