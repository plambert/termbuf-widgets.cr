# The primitives, all on one screen: a split with a rule you can drag, a
# virtualized list of a hundred thousand rows with a scrollbar, a scroll panel
# beside it, and a divider under a header.
#
#     crystal run examples/widgets.cr
#
# Tab moves the keyboard between the list and the panel, the arrows and the
# page keys move the selection, the wheel scrolls whatever is under the
# pointer, and the rule between the panes can be dragged. Press q to leave.
#
# The list holds no widget per row. Scrolling it to the hundred thousandth row
# costs the same as scrolling it to the third, because only the rows in the
# window are ever asked for.
require "../src/termbuf-widgets"

alias Widgets = TermBuf::Widgets

ROWS = 100_000

TermBuf::Terminal.open do |terminal|
  accent = TermBuf::Style::DEFAULT.fg TermBuf::Color.rgb(120, 180, 250)
  faint = TermBuf::Style::DEFAULT.faint

  # A source that is asked rather than held: nothing here is a hundred
  # thousand of anything.
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

  header = Widgets::Label.new " termbuf widgets"
  header.style = accent
  header.width = Widgets::Layout::Sizing.grow

  footer = Widgets::Label.new " tab moves focus · arrows and page keys move the " \
                              "selection · drag the rule · q to leave"
  footer.style = faint
  footer.width = Widgets::Layout::Sizing.grow

  root = Widgets::Panel.new(
    direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    margin: Widgets::Layout::Padding.all(0))
  root.add header, Widgets::Divider.new(label: "panes"), split, footer

  leaving = false
  keymap = Widgets::App.default_keymap.merge(Widgets::Bindings.build do |map|
    map.bind TermBuf::Key.parse("q"), "leave", ->(_context : Widgets::Context) { leaving = true; nil }
  end)

  app = Widgets::App.new terminal, root,
    TermBuf::Rect.full(terminal.size.columns, terminal.size.rows),
    terminal.events, terminal.policy, keymap

  # Reporting the mouse costs the person the terminal's own text selection, so
  # nothing turns it on uninvited. A demo of dragging a rule has to.
  terminal.enable TermBuf::Tty::MOUSE_SGR

  app.frame
  app.focus.focus list

  loop do
    app.frame { |spot| terminal.cursor.move_to spot[0], spot[1] if spot }
    terminal.paint

    break if leaving
    break unless app.wait
  end
end
