# A whole application: a field at the bottom, what has been answered above it,
# a paste notice, and a help overlay listing the keys that are live right now.
#
#     crystal run examples/field.cr
#
# Type and press enter to answer. Ctrl+G shows the keys. Escape or Ctrl+D on an
# empty line leaves. Tab completes a colour, up and down walk back through the
# answers, and pasted text goes in as text.
#
# Nothing here draws at a position. The layout puts the field along the bottom
# because the root aligns its children to the end of the column, so a resize
# needs no arithmetic: the tree is laid out again and everything follows.
#
# The panel above the field says the same thing on the screen, because an
# example is a manual test and the person running it should not have to read
# the source to tell working from broken. It is written out of the constants
# below, so a value changed here is changed there.
require "../src/termbuf-widgets"

alias Widgets = TermBuf::Widgets

COLOURS = %w[amber azure carmine cerulean chartreuse cobalt crimson indigo
  magenta ochre saffron scarlet sienna teal ultramarine vermilion]

# The most rows the field grows to before it scrolls inside itself.
MAX_ROWS = 8

# How many answers are kept on the screen above it.
KEPT = 12

# What the expectations are drawn in, and what the field's own text is.
EXPECTED_STYLE = TermBuf::Style::DEFAULT.faint

# What should be on the screen and what each key should do to it.
def expected : Widgets::Widget
  lines = [
    "A bordered field on the bottom row, titled a colour, with a › prompt.",
    "Empty it shows a faint placeholder; typing grows it to #{MAX_ROWS} rows.",
    "Enter answers: the line moves into the list above and the field empties.",
    "Tab completes one of #{COLOURS.size} colour names: #{COLOURS.first}, " \
    "#{COLOURS[1]}, and so on.",
    "Up and Down walk the answers already given, matched on what is typed.",
    "Paste: a notice shows while the bytes arrive and goes when they stop.",
    "Ctrl+G shows the keys that work right now, in the middle; again hides them.",
    "Escape, or Ctrl+D on an empty line, leaves.",
    "Resize: the field keeps the bottom row, the last #{KEPT} answers above it.",
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

# The root of the tree, and the one thing that knows what the application is
# for: it collects the lines the field hands over and hears when the paste
# notice should open and close.
class Session < Widgets::Panel
  # What has been answered, oldest first.
  getter answers = [] of String

  # Whether the line was given up on, or there is no more input coming.
  getter? finished = false

  # Opened and closed by the terminal's own paste reporting.
  property notice : Widgets::PasteNotice?

  def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
    case event
    when Widgets::Field::Accepted
      @answers << event.text
      context.consume
    when Widgets::Field::Cancelled, Widgets::Field::EndOfInput
      @finished = true
      context.consume
    when TermBuf::Events::Pasting
      @notice.try &.arriving(event.bytes)
    when TermBuf::Events::Paste
      @notice.try &.finished
    end
  end
end

TermBuf::Terminal.open do |terminal|
  accent = TermBuf::Style::DEFAULT.fg TermBuf::Color.rgb(120, 180, 250)
  faint = TermBuf::Style::DEFAULT.faint

  editor = Widgets::Editor.new(
    history: Widgets::History.new(search: Widgets::History::Search::Prefix),
    completions: ->(request : Widgets::Completion::Request) do
      Widgets::Completion::Result.new COLOURS.select(&.starts_with? request.word)
    end)

  field = Widgets::Field.new(
    editor: editor,
    border: Widgets::Border.rounded(title: " a colour ", style: accent),
    prompt: Widgets::Field::Prompt.new("› ", accent),
    growth: Widgets::Field::Growth::Grow,
    max_rows: MAX_ROWS,
    placeholder: "tab completes, up walks back, Ctrl+G for the keys")

  transcript = Widgets::Label.new "", wrap: Widgets::Layout::Wrap::Words
  transcript.width = Widgets::Layout::Sizing.grow
  transcript.style = faint

  # A float takes no room in the column and is drawn over it, so showing and
  # hiding the help moves nothing else on the screen.
  help = Widgets::Label.new "", wrap: Widgets::Layout::Wrap::None
  help.border = Widgets::Border.plain title: " keys "
  help.style = TermBuf::Style::DEFAULT.reverse
  help.hidden = true
  help.floating = Widgets::Layout::Floating.on nil,
    Widgets::Layout::AttachPoint::Center, Widgets::Layout::AttachPoint::Center, z: 50

  notice = Widgets::PasteNotice.new

  root = Session.new(
    direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    padding: Widgets::Layout::Padding.new(0, 1, 0, 1),
    gap: 1,
    align_y: Widgets::Layout::Align::End)
  root.notice = notice
  root.add expected, transcript, field, help, notice

  keymap = Widgets::App.default_keymap.merge(Widgets::Bindings.build do |map|
    map.bind TermBuf::Key.parse("Ctrl+G"), "show or hide these keys",
      ->(_context : Widgets::Context) { help.hidden = !help.hidden?; nil }
  end)

  app = Widgets::App.new terminal, root, TermBuf::Rect.full(terminal.size.columns, terminal.size.rows),
    terminal.events, terminal.policy, keymap

  app.frame
  app.focus.focus field
  terminal.hardware_cursor = terminal.cursor

  loop do
    transcript.text = root.answers.last(KEPT).join '\n'
    # Whatever the dispatch chain would answer, which is the field's map and
    # then the application's. The readline keys are not here: those live in the
    # editor's own map, which is keyed on what to do to the text rather than on
    # what to do to the tree, and the router never sees it.
    help.text = app.router.active_bindings.map do |binding, source|
      "#{binding.to_s.ljust 14} #{binding.description}#{source ? "" : "  (app)"}"
    end.join('\n') unless help.hidden?

    app.frame { |spot| terminal.cursor.move_to spot[0], spot[1] if spot }
    terminal.paint

    break if root.finished?
    break unless app.wait
  end
end
