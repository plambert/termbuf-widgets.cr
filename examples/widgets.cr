# The primitives, on four pages: a split with a rule you can drag over a
# virtualized list and a scroll panel, a table of a hundred thousand rows in
# fixed columns, a tree that loads a level at a time, and the navigation
# widgets.
#
#     crystal run examples/widgets.cr
#
# Press 1, 2, 3 and 4 for the pages. On every one of them Tab moves the
# keyboard, the arrows and the page keys move the selection, and the wheel
# scrolls whatever is under the pointer. On the panes page the rule between
# them can be dragged; on the tree page Right and Left open and close a node;
# on the navigation page Ctrl+PageUp and Ctrl+PageDown move between tabs.
# Press q to leave.
#
# None of the three holds a widget per row. Scrolling to the hundred thousandth
# row costs the same as scrolling to the third, because only the rows in the
# window are ever asked for.
require "../src/termbuf-widgets"

alias Widgets = TermBuf::Widgets

ROWS = 100_000

# How many children a node of the demonstration tree has at each level, and
# how deep it goes.
FANOUT = 4
DEPTH  = 3

# The panes page: a virtualized list on the left and a scroll panel on the
# right, with a rule between them that can be dragged.
def panes_page(accent : TermBuf::Style) : {Widgets::Widget, Widgets::Widget}
  rows = Widgets::Rows.from -> { ROWS }, ->(index : Int32) { "row #{index}" }

  list = Widgets::VirtualList.new rows
  list.on_draw = ->(view : TermBuf::View, _index : Int32, text : String, chosen : Bool) do
    view.write 0, 0, chosen ? "▸ #{text}" : "  #{text}",
      chosen ? TermBuf::Style::DEFAULT.reverse : TermBuf::Style::DEFAULT
    nil
  end

  left = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    border: Widgets::Border.rounded(title: " rows ", style: accent)
  left.add list, Widgets::Scrollbar.new(list)

  # A scroll panel is a window over real widgets, which is the other half of
  # the story: one row per thing, clipped rather than compressed.
  notes = Widgets::Scrollable.new
  40.times { |index| notes.add Widgets::Label.new("note #{index}") }

  right = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    border: Widgets::Border.plain(title: " notes ")
  right.add notes, Widgets::Scrollbar.new(notes)

  split = Widgets::Split.new left, right,
    direction: Widgets::Layout::Direction::Row, at: 30, minimum: 8

  {split, list}
end

# The table page: the same hundred thousand rows, in columns this time, with a
# header that stays put while they scroll.
def table_page(accent : TermBuf::Style) : {Widgets::Widget, Widgets::Widget}
  rows = Widgets::Rows.from -> { ROWS }, ->(index : Int32) { index }

  table = Widgets::Table.new rows
  table.add_column "row", ->(index : Int32) { index.to_s },
    Widgets::Layout::Sizing.fixed(8), align: TermBuf::Unicode::Align::Right
  table.add_column "name", ->(index : Int32) { "item number #{index}" },
    Widgets::Layout::Sizing.grow
  table.add_column "state", ->(index : Int32) { index.divisible_by?(3) ? "ready" : "waiting" },
    Widgets::Layout::Sizing.fixed(7),
    style: ->(index : Int32) do
      index.divisible_by?(3) ? accent : TermBuf::Style::DEFAULT.faint
    end

  panel = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    border: Widgets::Border.rounded(title: " table ", style: accent)
  panel.add table, Widgets::Scrollbar.new(table)

  {panel, table}
end

# The tree page: a source that makes each level up the moment it is asked for,
# which is what a tree over a filesystem or an API looks like.
def tree_page(accent : TermBuf::Style) : {Widgets::Widget, Widgets::Widget}
  nodes = Widgets::Nodes.from %w[root],
    children: ->(node : String) do
      Array.new(FANOUT) { |index| "#{node}/#{index}" }
    end,
    label: ->(node : String) { node.split('/').last },
    leaf: ->(node : String) { node.count('/') >= DEPTH }

  tree = Widgets::Tree.new nodes
  tree.expand "root"

  panel = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    border: Widgets::Border.rounded(title: " tree ", style: accent)
  panel.add tree, Widgets::Scrollbar.new(tree.list)

  {panel, tree.list}
end

# The navigation page: everything in the navigation group at once, so that the
# way they sit together can be seen rather than described.
def navigation_page(accent : TermBuf::Style) : {Widgets::Widget, Widgets::Widget}
  bar = Widgets::NavigationBar.new brand: "termbuf", trailing: "v0.1"
  bar.add "files", hint: "F1"
  bar.add "edit", hint: "F2"
  bar.add "view", hint: "F3"
  bar.style = accent

  crumbs = Widgets::Breadcrumbs.new %w[home projects termbuf widgets]
  crumbs.crumbs.first.uri = "file:///"

  tabs = Widgets::TabbedPanels.new height: Widgets::Layout::Sizing.grow(min: 6)
  tabs.add "summary", Widgets::Label.new("one tab is laid out; the rest are hidden widgets")
  tabs.add "detail", Widgets::Label.new("switching costs the layout of one subtree"),
    closable: true

  sections = Widgets::DisclosureGroup.new exclusive: true
  sections.add("general", expanded: true).body.add Widgets::Label.new("open")
  sections.add("advanced").body.add Widgets::Label.new("closed until it is asked for")

  pages = Widgets::Pagination.new pages: 24, page: 7

  panel = Widgets::Panel.new direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    gap: 1,
    padding: Widgets::Layout::Padding.all(1),
    border: Widgets::Border.rounded(title: " navigation ", style: accent)
  panel.add bar, crumbs, tabs, sections, pages

  {panel, bar}
end

# The overlays page: a button for each of them, and the overlays they put up.
#
# An overlay is opened on an application, and there is no application until the
# terminal is, so the page is built first and wired to one with `#attach`.
class OverlayPage < Widgets::Panel
  # The buttons, in the order they are shown.
  getter buttons : Array(Widgets::Button)

  # Where the toasts stack, or `nil` until the page is wired up.
  getter toasts : Widgets::Toasts? = nil

  @app : Widgets::App? = nil
  @dialog : Widgets::Dialog? = nil
  @menu : Widgets::DropdownMenu? = nil
  @drawer : Widgets::Drawer? = nil
  @answered : Widgets::Label

  def initialize(accent : TermBuf::Style)
    @buttons = ["dialog", "menu", "drawer", "toast"].map { |text| Widgets::Button.new text }
    @answered = Widgets::Label.new "nothing yet"

    super direction: Widgets::Layout::Direction::Column,
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow,
      padding: Widgets::Layout::Padding.all(1),
      gap: 1,
      border: Widgets::Border.rounded(title: " overlays ", style: accent)

    row = Widgets::Panel.new direction: Widgets::Layout::Direction::Row, gap: 2
    @buttons.each { |button| row.add button }
    add row, @answered
  end

  # Wires the page to *app*, which is what the overlays are opened on and where
  # the toasts stack.
  def attach(app : Widgets::App) : Nil
    @app = app
    @toasts = Widgets::Toasts.new app, corner: Widgets::Layout::AttachPoint::RightBottom
  end

  # Turns a press of one of the buttons into an overlay, and writes down what
  # the ones that answer had to say.
  def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
    case event
    when Widgets::Button::Pressed        then pressed event, context
    when Widgets::Dialog::Closed         then said "dialog: #{event.result || "cancelled"}"
    when Widgets::DropdownMenu::Selected then said "menu: #{event.item.label}"
    when Widgets::Drawer::Closed         then said "drawer: closed"
    end
  end

  private def pressed(event : Widgets::Button::Pressed, context : Widgets::Context) : Nil
    app = @app
    return unless app

    context.consume
    case @buttons.index &.same?(event.button)
    when 0 then confirm app
    when 1 then menu(app).open app
    when 2 then drawer(app).open app
    when 3 then @toasts.try &.show("something happened at #{Time.local.to_s("%H:%M:%S")}")
    end
  end

  private def said(what : String) : Nil
    @answered.text = what
  end

  private def confirm(app : Widgets::App) : Nil
    held = @dialog ||= Widgets::Dialog.new "leaving",
      body: Widgets::Label.new("go on, then?"), actions: %w[Yes No]
    held.open app
  end

  private def menu(app : Widgets::App) : Widgets::DropdownMenu
    @menu ||= Widgets::DropdownMenu.new @buttons[1], {
      Widgets::DropdownMenu::Item.new("Open", hint: "Ctrl+O"),
      Widgets::DropdownMenu::Item.new("Save", hint: "Ctrl+S"),
      Widgets::DropdownMenu::Item.new("Revert", enabled: false),
      Widgets::DropdownMenu::Item.new("Export", submenu: true),
    }
  end

  private def drawer(app : Widgets::App) : Widgets::Drawer
    held = @drawer
    return held if held

    made = Widgets::Drawer.new Widgets::Drawer::Edge::Right, size: 24,
      modal: true, backdrop: true, padding: Widgets::Layout::Padding.all(1),
      border: Widgets::Border.plain(title: " drawer ")
    made.add Widgets::Label.new("escape closes this")
    @drawer = made
  end
end

TermBuf::Terminal.open do |terminal|
  accent = TermBuf::Style::DEFAULT.fg TermBuf::Color.rgb(120, 180, 250)
  faint = TermBuf::Style::DEFAULT.faint

  overlays = OverlayPage.new accent
  pages = [panes_page(accent), table_page(accent), tree_page(accent),
           navigation_page(accent),
           {overlays.as(Widgets::Widget), overlays.buttons.first.as(Widgets::Widget)}]

  body = Widgets::Panel.new direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow
  pages.each_with_index do |page, index|
    page[0].hidden = index > 0
    body.add page[0]
  end

  header = Widgets::Label.new " termbuf widgets"
  header.style = accent
  header.width = Widgets::Layout::Sizing.grow

  footer = Widgets::Label.new " 1 panes · 2 table · 3 tree · 4 navigation · 5 overlays · " \
                              "f1 keys · tab moves focus · q to leave"
  footer.style = faint
  footer.width = Widgets::Layout::Sizing.grow

  root = Widgets::Panel.new(
    direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    margin: Widgets::Layout::Padding.all(0))
  root.add header, Widgets::Divider.new(label: "pages"), body, footer

  leaving = false
  keymap = Widgets::App.default_keymap.merge(Widgets::Bindings.build do |map|
    map.bind TermBuf::Key.parse("q"), "leave", ->(_context : Widgets::Context) { leaving = true; nil }

    pages.each_with_index do |page, index|
      map.bind TermBuf::Key.character('1' + index), "page #{index + 1}",
        ->(context : Widgets::Context) do
          pages.each_with_index { |other, place| other[0].hidden = place != index }
          context.focus.focus page[1]
          nil
        end
    end
  end)

  app = Widgets::App.new terminal, root,
    TermBuf::Rect.full(terminal.size.columns, terminal.size.rows),
    terminal.events, terminal.policy, keymap

  # Reporting the mouse costs the person the terminal's own text selection, so
  # nothing turns it on uninvited. A demo of dragging a rule has to.
  terminal.enable TermBuf::Tty::MOUSE_SGR

  # The widget layer opens no device, and a clock is one: a toast times out
  # only because the application handed over the terminal's.
  app.after = ->(span : Time::Span) { terminal.after span }
  app.cancel = ->(nonce : UInt64) { terminal.cancel nonce; nil }
  overlays.attach app
  Widgets::HelpOverlay.install app

  app.frame
  app.focus.focus pages.first[1]

  loop do
    app.frame { |spot| terminal.cursor.move_to spot[0], spot[1] if spot }
    terminal.paint

    break if leaving
    break unless app.wait
  end
end
