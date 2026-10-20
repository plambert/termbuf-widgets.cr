# A color picker, and two swatches showing what it chose at each depth.
#
#     crystal run examples/color.cr
#
# The arrows move over the grid, and Enter, Space or a click takes a color.
# Tab moves between the grid and the four fields. In a channel field the
# arrows step it, Home and End go to 0 and 255, and Enter clamps it. Ctrl+T
# switches the picker between true color and the 256 color palette. Ctrl+Q
# leaves.
#
# The panel at the top says what should be on the screen and what each key
# should do, because an example is a manual test. It is written out of the
# constants below, so a value changed here is changed there.
require "../src/termbuf-widgets"

alias Widgets = TermBuf::Widgets

# Where the picker starts, and what its "default" cell takes.
START   = TermBuf::Color.rgb 0x3080C0
DEFAULT = TermBuf::Color.rgb 0xC0C0C0

# What the expectations are drawn in.
EXPECTED_STYLE = TermBuf::Style::DEFAULT.faint

# What should be on the screen and what each key should do to it.
def expected : Widgets::Widget
  lines = [
    "Two swatches: the chosen color in true color, and as a 256 color terminal draws it.",
    "Under them the picker: its own swatch, a grid of colors, and the fields.",
    "Arrows move the [] cursor; Enter, Space or a click takes the color under it.",
    "Tab visits the grid, R, G, B and Hex, and wraps. Arrows step a channel.",
    "Home and End take a channel to 0 and 255; Enter clamps what was typed.",
    "Typing a channel or a whole hex value moves the swatches as you type.",
    "Ctrl+T switches to 256 colors: the system colors appear on top of the grid,",
    "and a field edit snaps to the nearest index when Tab leaves the field.",
    "The default cell at the end of the grey row takes #{Widgets::Depth.hex DEFAULT}.",
    "The line under the picker counts the changes it has sent. Ctrl+Q leaves.",
  ]

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

# The root of the tree. It hears every change the picker sends and passes the
# color on to the two swatches.
class Session < Widgets::Panel
  # How many changes have arrived.
  getter changes = 0

  # The swatches that follow the picker.
  property followers = [] of Widgets::ColorSwatch

  # What says how many changes have arrived.
  property report : Widgets::Label?

  def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
    return unless event.is_a? Widgets::ColorPicker::Changed

    @changes += 1
    @followers.each &.color=(event.color)
    @report.try &.text=("#{@changes} changes, the last #{event.color}")
    context.consume
  end
end

TermBuf::Terminal.open do |terminal|
  true_color = Widgets::ColorSwatch.new START
  palette = Widgets::ColorSwatch.new START, depth: Widgets::Depth::Indexed256

  picker = Widgets::ColorPicker.new START, reset_to: DEFAULT
  picker.border = Widgets::Border.rounded title: " picker "

  report = Widgets::Label.new "no changes yet"
  report.style = EXPECTED_STYLE

  root = Session.new(
    direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    padding: Widgets::Layout::Padding.new(0, 1, 0, 1),
    gap: 1)
  root.followers = [true_color, palette]
  root.report = report
  root.add expected, true_color, palette, picker, report

  leaving = false
  keymap = Widgets::App.default_keymap.merge(Widgets::Bindings.build do |map|
    map.bind TermBuf::Key.parse("Ctrl+Q"), "leave",
      ->(_context : Widgets::Context) { leaving = true; nil }
    map.bind TermBuf::Key.parse("Ctrl+T"), "switch the picker's depth",
      ->(_context : Widgets::Context) do
        to_palette = picker.depth.true_color?
        picker.depth = to_palette ? Widgets::Depth::Indexed256 : Widgets::Depth::TrueColor

        # A new depth can move the value without a `Changed`, so the swatches
        # are told here.
        root.followers.each &.color=(picker.value)
        nil
      end
  end)

  app = Widgets::App.new terminal, root,
    TermBuf::Rect.full(terminal.size.columns, terminal.size.rows),
    terminal.events, terminal.policy, keymap

  # A click on the grid needs the mouse reported.
  terminal.enable TermBuf::Tty::MOUSE_SGR

  app.frame
  terminal.hardware_cursor = terminal.cursor

  loop do
    app.frame { |spot| terminal.cursor.move_to spot[0], spot[1] if spot }
    terminal.paint

    break if leaving
    break unless app.wait
  end
end
