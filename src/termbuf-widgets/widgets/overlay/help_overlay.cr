require "../../router"
require "../rows"
require "../virtual_list"
require "./dialog"

module TermBuf::Widgets
  # A dialog listing the keys that would work right now.
  #
  #     help = HelpOverlay.install app
  #
  # What it shows is `Router#active_bindings`: every binding the chain from the
  # focused widget up would answer, innermost first, grouped by the widget it
  # came from. The list is read when the overlay opens rather than when it is
  # built, and it is read before the modal scope goes on, so what it shows is
  # what was in scope a moment ago rather than what the help overlay itself
  # binds.
  #
  # `.install` binds `F1` and `?` under the whole application by merging them
  # into `App#keymap`, which leaves whatever was there. An application that
  # would rather bind it somewhere else can leave that alone and call `#open`
  # from its own binding.
  class HelpOverlay < Dialog
    # One line: either the name of a group or a binding in it.
    record Row, keys : String, description : String, header : Bool = false

    # The keys `.install` binds by default.
    DEFAULT_KEYS = {"F1", "?"}

    # What a group of bindings that came from the focus scope rather than from
    # a widget is called.
    SCOPE = "application"

    # The list the rows are drawn through.
    #
    # A `VirtualList` that measures its own content, the same way a
    # `DropdownMenu::List` does, so the dialog around it can fit what it holds.
    class List < VirtualList(Row)
      # Cells between the keys and what they do.
      GAP = 2

      # The most rows shown at once. Anything past that scrolls.
      layout_property max_rows : Int32 = 14

      # How wide the keys column is, which is what the descriptions line up
      # against.
      def keys_width : Int32
        @keys_width
      end

      @keys_width : Int32 = 0

      # Marks the tree stale as well as changing the rows, because how wide the
      # list wants to be comes from what is in it.
      def rows=(rows : Rows(Row)) : Rows(Row)
        result = super
        invalidate_layout
        result
      end

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        @keys_width = 0
        widest = 0

        rows.size.times do |index|
          row = rows.row index
          if row.header
            widest = Math.max widest, Unicode.string_width(row.keys, policy)
            next
          end

          @keys_width = Math.max @keys_width, Unicode.string_width(row.keys, policy)
        end

        rows.size.times do |index|
          row = rows.row index
          next if row.header

          widest = Math.max widest,
            @keys_width + GAP + Unicode.string_width(row.description, policy)
        end

        Layout::Intrinsic.new Math.min(widest, 8), widest
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        Math.max Math.min(rows.size, @max_rows), 1
      end
    end

    # The rows as they stand, rebuilt every time the overlay opens.
    getter rows = [] of Row

    # The list they are drawn through.
    getter list : List

    # What a group heading is drawn in.
    property header_style : Style = Style::DEFAULT.bold

    # What a key sequence is drawn in.
    property keys_style : Style = Style::DEFAULT

    # What the description of a binding is drawn in.
    property description_style : Style = Style::DEFAULT.faint

    def initialize(title : String? = "keys",
                   actions : Enumerable(String) = {"Close"},
                   max_rows : Int32 = 14,
                   z : Int32 = Z::DIALOG,
                   backdrop : Bool = true,
                   border : Border? = nil,
                   style : Style? = nil)
      # Built before the dialog is, because the dialog puts it in with an
      # `Widget#add` and every one of those reaches back through `self`.
      @list = List.new Rows.of(@rows), width: Layout::Sizing.fit,
        height: Layout::Sizing.fit(min: 1)
      @list.max_rows = max_rows

      super title, body: @list, actions: actions, z: z, backdrop: backdrop,
        border: border, style: style
    end

    # Reads the bindings that are in scope and turns them into rows.
    #
    # Called by `Overlay#open` before the modal scope goes on, so the chain it
    # asks about is the one that was there a moment ago.
    def refresh(app : App) : Nil
      @rows.clear
      group_of(app).each do |source, bindings|
        @rows << Row.new source, "", header: true
        bindings.each do |binding|
          @rows << Row.new binding.to_s, binding.description
        end
      end

      @list.rows = Rows.of @rows
      @list.select first_binding
      @list.scroll_to_row 0
    end

    # :inherit:
    protected def prepare(app : App) : Nil
      refresh app
      @list.on_draw = ->(view : View, _index : Int32, row : Row, chosen : Bool, _focused : Bool) do
        draw_row view, row, chosen
      end
    end

    # The keyboard goes to the list, so that the arrows scroll it.
    protected def initial_focus : Widget?
      @list
    end

    # Puts *help* up on `F1` and `?`, or on *keys*, and answers it.
    #
    # The bindings are merged into `App#keymap` rather than replacing it, so
    # whatever was already bound under the application stays bound.
    def self.install(app : App, help : HelpOverlay = new,
                     keys : Enumerable(String) = DEFAULT_KEYS) : HelpOverlay
      map = Bindings.new
      keys.each do |key|
        map.bind Key.parse(key), "show the keys that work here",
          ->(_context : Context) { help.open app; nil }
      end

      app.keymap = app.keymap.merge map
      help
    end

    # The bindings in scope, in groups, each named for where it came from.
    #
    # `Router#active_bindings` answers innermost first, and the groups come out
    # in that order: the widget with the keyboard, then whatever holds it, and
    # the application's own last.
    private def group_of(app : App) : Array({String, Array(Keymap::Binding(Action))})
      groups = [] of {String, Array(Keymap::Binding(Action))}

      app.router.active_bindings.each do |binding, widget|
        name = widget ? name_of(widget) : SCOPE
        last = groups.last?
        if last && last[0] == name
          last[1] << binding
        else
          groups << {name, [binding]}
        end
      end

      groups
    end

    # What a widget's group is called: the class without its namespace, which
    # is what a reader recognises.
    private def name_of(widget : Widget) : String
      widget.class.name.split("::").last
    end

    # The first row that is a binding rather than a heading, so the highlight
    # never starts on a group name.
    private def first_binding : Int32
      @rows.index { |row| !row.header } || 0
    end

    # Draws one row: a heading, or a key sequence and what it does.
    private def draw_row(view : View, row : Row, chosen : Bool) : Nil
      return if view.width <= 0

      if row.header
        view.write 0, 0, Unicode.truncate(row.keys, view.width, view.policy), @header_style
        return
      end

      keys = @keys_style
      keys = keys.reverse if chosen
      view.write 0, 0, Unicode.truncate(row.keys, view.width, view.policy), keys

      spot = @list.keys_width + List::GAP
      return if spot >= view.width

      view.write spot, 0,
        Unicode.truncate(row.description, view.width - spot, view.policy),
        @description_style
    end
  end
end
