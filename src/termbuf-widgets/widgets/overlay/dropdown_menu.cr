require "../../message"
require "../rows"
require "../virtual_list"
require "./popover"

module TermBuf::Widgets
  # A list of commands hanging off whatever opened it.
  #
  #     menu = DropdownMenu.new button, {
  #       DropdownMenu::Item.new("Open", hint: "Ctrl+O"),
  #       DropdownMenu::Item.new("Save", hint: "Ctrl+S"),
  #       DropdownMenu::Item.new("Revert", enabled: false),
  #     }
  #     menu.open app
  #
  # A `Popover` holding a `VirtualList`, so a menu of five items and a menu of
  # five thousand cost the same to draw. Up and down move the highlight, past
  # anything disabled; `Enter` and a click choose; `Escape` and a click outside
  # take the menu down. Choosing says `Selected` and closes.
  #
  # There is no menu bar here: a row of buttons each opening one of these is
  # what a menu bar is, and it belongs to the application that wants one.
  class DropdownMenu < Popover
    # One line of the menu.
    #
    # *hint* is the key binding shown against the right edge, and does not bind
    # anything: what the key does belongs to the keymap that owns it. *submenu*
    # only draws the marker, since what opening one means is another menu the
    # application puts up.
    record Item,
      label : String,
      hint : String? = nil,
      enabled : Bool = true,
      submenu : Bool = false

    # An item was chosen.
    struct Selected < Message
      # Which menu it was.
      getter menu : DropdownMenu

      # Which item, counting from zero.
      getter index : Int32

      # The item itself.
      getter item : Item

      def initialize(@menu : DropdownMenu, @index : Int32, @item : Item)
      end
    end

    # The list a menu is drawn as, which is a `VirtualList` that knows how wide
    # its widest line is.
    #
    # `VirtualList` asks for one cell and no more, because it holds no widget
    # per row and cannot measure what it does not build. A menu can: its rows
    # are strings, and the width is the widest label, its hint and the marker
    # for a submenu.
    class List < VirtualList(Item)
      # Cells between a label and the hint against the right edge.
      GAP = 2

      # The marker drawn against the right edge of an item that opens another
      # menu.
      SUBMENU = "▸"

      # The most rows the menu shows at once. Anything past that scrolls.
      layout_property max_rows : Int32 = 12

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        widest = 0
        rows.size.times do |index|
          widest = Math.max widest, width_of(rows.row(index), policy)
        end

        Layout::Intrinsic.new Math.min(widest, 4), widest
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        Math.max Math.min(rows.size, @max_rows), 1
      end

      # How many cells one item wants.
      private def width_of(item : Item, policy : Unicode::WidthPolicy) : Int32
        wanted = Unicode.string_width item.label, policy
        if hint = item.hint
          wanted += GAP + Unicode.string_width hint, policy
        end
        wanted += GAP + Unicode.string_width SUBMENU, policy if item.submenu
        wanted
      end
    end

    # The items, in the order they are shown. Changing this in place is what
    # the list reads on the next frame.
    getter items : Array(Item)

    # The list the items are drawn through.
    getter list : List

    # What a disabled item is drawn in.
    property disabled_style : Style = Style::DEFAULT.faint

    # What the highlighted item is drawn in.
    property selected_style : Style = Style::DEFAULT.reverse

    # What a hint against the right edge is drawn in.
    property hint_style : Style = Style::DEFAULT.faint

    def initialize(target : Widget? = nil,
                   items : Enumerable(Item) = [] of Item,
                   element : Layout::AttachPoint = Layout::AttachPoint::LeftTop,
                   parent : Layout::AttachPoint = Layout::AttachPoint::LeftBottom,
                   dx : Int32 = 0,
                   dy : Int32 = 0,
                   z : Int32 = Z::POPOVER,
                   max_rows : Int32 = 12,
                   modal : Bool = false,
                   light_dismiss : Bool = true,
                   border : Border? = Border.plain,
                   style : Style? = nil)
      # Both are built before the popover is, because putting the list in is an
      # `Widget#add` and every one of those reaches back through `self`.
      @items = items.to_a
      @list = List.new Rows.of(@items), width: Layout::Sizing.fit,
        height: Layout::Sizing.fit(min: 1)
      @list.max_rows = max_rows

      super target, content: @list, element: element, parent: parent,
        dx: dx, dy: dy, z: z, modal: modal, light_dismiss: light_dismiss,
        border: border, style: style

      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fit
      @list.on_draw = ->(view : View, _index : Int32, item : Item, chosen : Bool, _focused : Bool) do
        draw_item view, item, chosen
      end
      @list.keymap = moves
    end

    # The item the highlight is on, or `nil` for an empty menu.
    def current : Item?
      @items[@list.selected]?
    end

    # Which item the highlight is on.
    def selected : Int32
      @list.selected
    end

    # Puts the highlight on *index*, or on the next item after it that can be
    # chosen when that one cannot.
    #
    # Named `highlight` rather than `select` because `select` is a keyword: a
    # call to one without a receiver does not parse.
    def highlight(index : Int32) : Nil
      return if @items.empty?

      wanted = index.clamp 0, @items.size - 1
      return @list.select wanted if @items[wanted].enabled

      moved = search wanted, 1
      @list.select moved if moved
    end

    # Moves the highlight *step* places, past anything disabled, wrapping at
    # either end.
    def step(step : Int32) : Nil
      moved = search @list.selected, step
      @list.select moved if moved
    end

    # Chooses the item the highlight is on, if it can be chosen.
    def choose : Nil
      index = @list.selected
      item = @items[index]?
      return if item.nil? || !item.enabled

      emit Selected.new self, index, item
      close
    end

    # Takes the pointer: moving it over an item highlights that item, and
    # pressing on one chooses it.
    def handle(event : Event, context : Context) : Nil
      return super unless event.is_a? Events::Mouse

      row = row_at event.x, event.y
      return super unless row

      case event.action
      in .motion?  then highlight row
      in .press?   then choose_at row, context
      in .release? then nil
      end
    end

    # The highlight starts on something that can be chosen.
    protected def prepare(app : App) : Nil
      highlight @list.selected
    end

    # The keyboard goes to the list, which is what the arrows are for.
    protected def initial_focus : Widget?
      @list
    end

    # Highlights *row* and chooses it.
    private def choose_at(row : Int32, context : Context) : Nil
      highlight row
      return unless @list.selected == row

      context.consume
      choose
    end

    # Which item the point (*x*, *y*) is on, or `nil` for a point off the
    # list.
    private def row_at(x : Int32, y : Int32) : Int32?
      box = @list.content
      return unless box.contains? x, y

      row = @list.visible_range.begin + (y - box.y)
      return unless 0 <= row < @items.size

      row
    end

    # The first item *step* places on from *from* that can be chosen, or `nil`
    # when there is not one.
    private def search(from : Int32, step : Int32) : Int32?
      count = @items.size
      return if count.zero? || step.zero?

      index = from
      count.times do
        index = (index + step) % count
        return index if @items[index].enabled
      end

      nil
    end

    # Draws one item: its label, its hint against the right edge, and the
    # marker for a submenu.
    private def draw_item(view : View, item : Item, chosen : Bool) : Nil
      return if view.width <= 0

      paint = if !item.enabled
                @disabled_style
              elsif chosen
                @selected_style
              else
                Style::DEFAULT
              end

      view.fill view.bounds, ' ', paint
      view.write 0, 0, Unicode.truncate(item.label, view.width, view.policy), paint

      right = view.width
      if item.submenu
        right -= Unicode.string_width List::SUBMENU, view.policy
        view.write right, 0, List::SUBMENU, paint
      end

      hint = item.hint
      return unless hint

      wanted = Unicode.string_width hint, view.policy
      spot = right - wanted
      return if spot <= Unicode.string_width(item.label, view.policy)

      view.write spot, 0, hint, chosen ? paint : paint.merge(@hint_style)
    end

    # The keys that move the highlight and choose an item.
    private def moves : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Up"), "the item before", ->(_context : Context) { step(-1) }
        map.bind Key.parse("Down"), "the item after", ->(_context : Context) { step 1 }
        map.bind Key.parse("Home"), "the first item", ->(_context : Context) { highlight 0 }
        map.bind Key.parse("End"), "the last item",
          ->(_context : Context) { last_enabled }
        map.bind Key.parse("Enter"), "choose it", ->(_context : Context) { choose }
      end
    end

    # Puts the highlight on the last item that can be chosen.
    private def last_enabled : Nil
      moved = search 0, -1
      @list.select moved if moved
    end
  end
end
