# The primitives, on six pages: a split with a rule you can drag over a
# virtualized list and a scroll panel, a table of a hundred thousand rows in
# fixed columns, a tree that loads a level at a time, the navigation widgets,
# the overlays, and the display widgets that move on their own.
#
#     crystal run examples/widgets.cr
#
# Press 1 to 6 for the pages. On every one of them Tab moves the keyboard, the
# arrows and the page keys move the selection, and the wheel scrolls whatever
# is under the pointer. On the panes page the rule between them can be dragged;
# on the tree page Right and Left open and close a node; on the navigation page
# Ctrl+PageUp and Ctrl+PageDown move between tabs; on the display page the link
# reveals its address when the keyboard reaches it, Enter follows it and c
# copies it. Press q to leave.
#
# None of the three holds a widget per row. Scrolling to the hundred thousandth
# row costs the same as scrolling to the third, because only the rows in the
# window are ever asked for.
#
# Every page carries a panel saying what should be on the screen and what each
# key should do to it, because an example is a manual test and a test that does
# not say what passing looks like is not one. The panels are written out of the
# same constants the pages are built from, so a value changed in one place is
# changed in both.
require "../src/termbuf-widgets"

alias Widgets = TermBuf::Widgets

ROWS = 100_000

# Widgets in the scroll panel on the right of the panes page.
NOTES = 40

# Where the rule between the panes starts, and the fewest cells either pane
# can be dragged down to.
SPLIT_AT      = 30
SPLIT_MINIMUM =  8

# How many children a node of the demonstration tree has at each level, and
# how deep it goes.
FANOUT = 4
DEPTH  = 3

# The pagination widget on the navigation page.
PAGE_COUNT = 24
PAGE_SHOWN =  7

# What the rating on the display page reads, out of how many stars.
RATING     = 3.5
RATING_MAX =   5

# How far back the relative time on the display page points.
AGO = 90.seconds

# How full the progress bar on the display page is.
PROGRESS = 0.62

# What the expectations are drawn in: quiet enough to leave the widgets the
# eye, plain enough to read.
EXPECTED_STYLE = TermBuf::Style::DEFAULT.faint

# What a pane's border is drawn in while the keyboard is somewhere else. The
# focused one takes the accent colour, so the two have to differ.
PANE_STYLE = TermBuf::Style::DEFAULT.faint

# The panel at the top of a page: one line per thing demonstrated, saying what
# it should show and what should happen when it is used.
def expected(*lines : String) : Widgets::Widget
  panel = Widgets::Panel.new direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    padding: Widgets::Layout::Padding.symmetric(horizontal: 1),
    border: Widgets::Border.plain(title: " expected ", style: EXPECTED_STYLE,
      title_style: EXPECTED_STYLE)

  lines.each do |line|
    label = Widgets::Label.new line, wrap: Widgets::Layout::Wrap::Words
    label.width = Widgets::Layout::Sizing.grow
    label.style = EXPECTED_STYLE
    panel.add label
  end

  panel
end

# A page: what it demonstrates, under the panel saying what it should do.
def paged(content : Widgets::Widget, *lines : String) : Widgets::Widget
  panel = Widgets::Panel.new direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow
  panel.add expected(*lines), content
  panel
end

# The panes page: a virtualized list on the left and a scroll panel on the
# right, with a rule between them that can be dragged.
def panes_page(accent : TermBuf::Style) : {Widgets::Widget, Widgets::Widget}
  rows = Widgets::Rows.from -> { ROWS }, ->(index : Int32) { "row #{index}" }

  list = Widgets::VirtualList.new rows
  # The mark says which row is chosen whatever has the keyboard; the reverse
  # video says the arrows will move it, so it is drawn only while the list has
  # the keyboard.
  list.on_draw = ->(view : TermBuf::View, _index : Int32, text : String, chosen : Bool, focused : Bool) do
    view.write 0, 0, chosen ? "▸ #{text}" : "  #{text}",
      chosen && focused ? TermBuf::Style::DEFAULT.reverse : TermBuf::Style::DEFAULT
    nil
  end

  left = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    border: Widgets::Border.rounded(title: " rows ", style: PANE_STYLE)
  left.focused_border_style = accent
  left.add list, Widgets::Scrollbar.new(list)

  # A scroll panel is a window over real widgets, which is the other half of
  # the story: one row per thing, clipped rather than compressed. Nothing in it
  # can take the keyboard, so the panel takes it itself and the arrows scroll.
  notes = Widgets::Scrollable.new
  NOTES.times { |index| notes.add Widgets::Label.new("note #{index}") }

  right = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    border: Widgets::Border.plain(title: " notes ", style: PANE_STYLE)
  right.focused_border_style = accent
  right.add notes, Widgets::Scrollbar.new(notes)

  split = Widgets::Split.new left, right,
    direction: Widgets::Layout::Direction::Row, at: SPLIT_AT, minimum: SPLIT_MINIMUM

  page = paged split,
    "Left: #{ROWS} rows, the chosen one marked ▸. Right: #{NOTES} note widgets.",
    "Drag the rule, which starts #{SPLIT_AT} cells in: both panes resize, and " \
    "neither is let below #{SPLIT_MINIMUM} cells.",
    "The wheel over a pane scrolls that one, and its scrollbar follows.",
    "Tab moves between list and notes, and the pane with the keyboard is the " \
    "one whose border is in the accent colour.",
    "On the list, Up, Down, PageUp, PageDown, Home and End move the chosen " \
    "row, which is in reverse video only while the list has the keyboard.",
    "On the notes the same keys scroll the pane, a row or a window at a time."

  {page, list}
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

  page = paged panel,
    "#{ROWS} rows: row (8 cells, right), name (what is left), state (7 cells, " \
    "ready in the accent colour every third row, a faint waiting on the rest).",
    "The header stays where it is while the rows move under it.",
    "End reaches row #{ROWS - 1} at once and Home row 0: a row is built only " \
    "while it is on the screen.",
    "A name too wide for its column ends in …; the columns keep their widths."

  {page, table}
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

  page = paged panel,
    "root is open; #{FANOUT} children to a node, #{DEPTH} levels deep.",
    "Right opens the chosen node, asking for its children the first time only.",
    "Left closes an open node, or moves to the parent of a closed one.",
    "Enter uses a leaf, which is a node #{DEPTH} deep.",
    "Up and Down walk the rows showing, not the whole tree."

  {page, tree.list}
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

  pages = Widgets::Pagination.new pages: PAGE_COUNT, page: PAGE_SHOWN

  panel = Widgets::Panel.new direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    gap: 1,
    padding: Widgets::Layout::Padding.all(1),
    border: Widgets::Border.rounded(title: " navigation ", style: accent)
  panel.add bar, crumbs, tabs, sections, pages

  page = paged panel,
    "Bar: termbuf, v0.1, over files, edit, view (F1 to F3); Left, Right, Enter.",
    "Crumbs: home, projects, termbuf, widgets; home is a link a click follows.",
    "Tabs: summary, detail (closable); Ctrl+PageUp, Ctrl+PageDown, Enter goes in.",
    "Sections: general open, advanced shut, one at a time; Enter or Space.",
    "Pagination: page #{PAGE_SHOWN} of #{PAGE_COUNT}; Left and Right step, Home " \
    "and End the ends.",
    "Tab moves the keyboard through the five, in that order."

  {page, bar}
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

  # The page's own ground, which is what the dialog and the drawer dim. A
  # terminal on a black background shows nothing of a backdrop that halves
  # colours the page never named.
  GROUND = TermBuf::Style.new background: TermBuf::Color.rgb(30, 45, 80)

  # The colours of the text behind the overlays, chosen to be worth halving.
  WARM = TermBuf::Style.new foreground: TermBuf::Color.rgb(200, 120, 60),
    background: TermBuf::Color.rgb(30, 45, 80)
  COOL = TermBuf::Style.new foreground: TermBuf::Color.rgb(90, 190, 120),
    background: TermBuf::Color.rgb(30, 45, 80)

  # How wide the drawer is when it comes out.
  DRAWER_CELLS = 24

  # What the dialog offers.
  ANSWERS = %w[Yes No]

  def initialize(accent : TermBuf::Style)
    @buttons = ["dialog", "menu", "drawer", "toast"].map { |text| Widgets::Button.new text }
    @answered = Widgets::Label.new "nothing yet"

    super direction: Widgets::Layout::Direction::Column,
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow,
      padding: Widgets::Layout::Padding.all(1),
      gap: 1,
      style: GROUND,
      border: Widgets::Border.rounded(title: " overlays ", style: accent)

    row = Widgets::Panel.new direction: Widgets::Layout::Direction::Row, gap: 2
    @buttons.each { |button| row.add button }
    behind = Widgets::Label.new "and this line dims while one of them is up"
    behind.style = COOL
    add expectations, row, @answered, ground_row, behind
  end

  # What the four buttons should put up, and what each overlay should do.
  private def expectations : Widgets::Widget
    expected "Tab between the four; Enter, Space or a click opens one.",
      "dialog: leaving, go on, then?, with #{ANSWERS.join " and "}; Escape cancels.",
      "menu: Open, Save, Revert (greyed), Export (submenu); Escape shuts it.",
      "drawer: right edge, #{DRAWER_CELLS} cells wide; Escape shuts it.",
      "toast: bottom right, gone by itself after " \
      "#{Widgets::Toasts::DEFAULT_TTL.total_seconds.to_i} seconds.",
      "Dialog and drawer dim this page, keeping its colours; nothing is erased.",
      "The line under the buttons says what the last overlay answered."
  end

  # A row of coloured text where the dialog and the drawer land, so that the
  # dimming has something to dim.
  private def ground_row : Widgets::Widget
    row = Widgets::Panel.new direction: Widgets::Layout::Direction::Row, gap: 2
    %w[behind the overlay].each do |word|
      label = Widgets::Label.new word
      label.style = WARM
      row.add label
    end
    row
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
      body: Widgets::Label.new("go on, then?"), actions: ANSWERS
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

    made = Widgets::Drawer.new Widgets::Drawer::Edge::Right, size: DRAWER_CELLS,
      modal: true, backdrop: true, padding: Widgets::Layout::Padding.all(1),
      border: Widgets::Border.plain(title: " drawer ")
    made.add Widgets::Label.new("escape closes this")
    @drawer = made
  end
end

# The display page: the widgets that say what something is, including the three
# that move on their own.
#
# A spinner turns, a clock keeps up and a relative time ages, all on timers the
# application lends them, so the page is built first and wired to one with
# `#attach` the way the overlays page is.
class DisplayPage < Widgets::Panel
  # The link, which is what the keyboard lands on when the page is chosen.
  getter link : Widgets::Hyperlink

  @spinner : Widgets::Spinner
  @clock : Widgets::Clock
  @ago : Widgets::RelativeTime
  @copy : Widgets::CopyButton
  @rating : Widgets::Rating

  URL = "https://sw.kovidgoyal.net/kitty/graphics-protocol/"

  # What the clock is drawn in, which is what the reading should look like.
  FORMAT = "%H:%M:%S"

  # How wide the picture is, and how many rows deep.
  SWATCH_COLUMNS = 8
  SWATCH_ROWS    = 2

  # What is drawn where the terminal draws no pictures.
  ALT = "[no pictures]"

  def initialize(accent : TermBuf::Style)
    @spinner = Widgets::Spinner.new "working"
    @clock = Widgets::Clock.new FORMAT
    @ago = Widgets::RelativeTime.new Time.local - AGO
    @link = Widgets::Hyperlink.new "the graphics protocol", URL
    @copy = Widgets::CopyButton.new "copy the address", -> { URL }
    @rating = Widgets::Rating.new RATING, max: RATING_MAX, editable: true

    super direction: Widgets::Layout::Direction::Column,
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow,
      padding: Widgets::Layout::Padding.all(1),
      gap: 1,
      border: Widgets::Border.rounded(title: " display ", style: accent)

    add expectations, moving_row, stamps_row, icons_row, @link, @copy
  end

  # What each of the widgets on this page should show, and what should happen
  # to the ones that can be used.
  private def expectations : Widgets::Widget
    expected "Spinner turning by itself; bar #{(PROGRESS * 100).round.to_i}% full, " \
             "the figure written in it.",
      "Clock #{FORMAT}, on the second; the date is fixed; the third reading ages " \
      "from #{AGO.total_seconds.to_i} seconds back.",
      "Icons: star, dot, folder, each with a plainer spelling in reserve.",
      "Rating #{RATING} of #{RATING_MAX}: #{RATING.to_i} stars, one dimmed for the " \
      "half, #{RATING_MAX - RATING.to_i - 1} empty; never a box.",
      "On the rating Left and Right change it and the digits set it, so 1 to 6 wait.",
      "Picture: a #{SWATCH_COLUMNS} by #{SWATCH_ROWS} gradient, or #{ALT}.",
      "Link: Tab reveals the address below; Enter follows, c copies.",
      "Button: Enter says #{@copy.copied_text} for #{@copy.flash.total_seconds.to_i} " \
      "seconds, or #{@copy.unavailable_text} where there is none."
  end

  # Wires the page to *app*: the link and the button want its clipboard, and
  # the three moving widgets want its clock.
  def attach(app : Widgets::App) : Nil
    @link.attach app
    @copy.attach app
    @spinner.start app
    @clock.start app
    @ago.start app
  end

  # A spinner and a bar, which are the two ways of saying work is going on.
  private def moving_row : Widgets::Widget
    bar = Widgets::ProgressBar.new PROGRESS,
      width: Widgets::Layout::Sizing.fixed(24),
      label: Widgets::ProgressBar::Placement::Centre

    row = Widgets::Panel.new direction: Widgets::Layout::Direction::Row, gap: 3
    row.add @spinner, bar
    row
  end

  # The time now, the date, and how long ago something was.
  private def stamps_row : Widgets::Widget
    row = Widgets::Panel.new direction: Widgets::Layout::Direction::Row, gap: 3
    row.add @clock, Widgets::DateDisplay.new(Time.local), @ago
    row
  end

  # Glyphs with a plainer spelling behind each of them, and a picture nothing
  # but a terminal with the graphics protocol will show.
  private def icons_row : Widgets::Widget
    row = Widgets::Panel.new direction: Widgets::Layout::Direction::Row, gap: 2
    row.add Widgets::Icon.new("★", fallback: "*"),
      Widgets::Icon.new("●", fallback: "o"),
      Widgets::Icon.new("📁", fallback: "[]"),
      @rating,
      Widgets::Picture.new(swatch, columns: SWATCH_COLUMNS, rows: SWATCH_ROWS, alt: ALT)
    row
  end

  # A small gradient, made here rather than read off disk so the example needs
  # nothing beside it.
  private def swatch : TermBuf::Image
    side = 32
    pixels = Bytes.new side * side * 3
    side.times do |row|
      side.times do |column|
        at = (row * side + column) * 3
        pixels[at] = (column * 255 // side).to_u8
        pixels[at + 1] = (row * 255 // side).to_u8
        pixels[at + 2] = 160_u8
      end
    end

    TermBuf::Image.rgb pixels, side, side
  end
end

TermBuf::Terminal.open do |terminal|
  accent = TermBuf::Style::DEFAULT.fg TermBuf::Color.rgb(120, 180, 250)
  faint = TermBuf::Style::DEFAULT.faint

  overlays = OverlayPage.new accent
  display = DisplayPage.new accent
  pages = [panes_page(accent), table_page(accent), tree_page(accent),
           navigation_page(accent),
           {overlays.as(Widgets::Widget), overlays.buttons.first.as(Widgets::Widget)},
           {display.as(Widgets::Widget), display.link.as(Widgets::Widget)}]

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
                              "6 display · f1 keys · tab moves focus · q to leave"
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

  # The same bargain for the clipboard: the terminal owns the connection to the
  # window system, and a widget that copies is handed the application.
  app.copy = ->(text : String) { terminal.clipboard.copy text }

  # And for pictures, which a widget asks for through the store rather than
  # drawing itself.
  app.images = terminal.images

  overlays.attach app
  display.attach app
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
