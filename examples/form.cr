# Two forms side by side. On the left is a settings form built from a schema,
# with every row kind and no buttons. On the right is a dialog form of fields
# with Submit and Cancel.
#
#     crystal run examples/form.cr
#
# Up and Down move between rows in a form, and Tab moves through the rows and on
# into the other form. Space toggles, Left and Right move a choice or step a
# number, Enter or Space presses an action row, and typing edits a text row. The
# settings form is taller than its window on a short terminal, so it scrolls as
# the keyboard moves. The line at the bottom says what the last message was.
# Ctrl+Q leaves.
#
# The panel at the top says the same thing on the screen, because an example is
# a manual test and the person running it should not have to read the source to
# tell working from broken.
require "../src/termbuf-widgets"

alias Widgets = TermBuf::Widgets

# What the expectations are drawn in.
EXPECTED_STYLE = TermBuf::Style::DEFAULT.faint

# How many cells the dialog form takes across.
DIALOG_WIDTH = 34

# What should be on the screen and what each key should do to it.
def expected : Widgets::Widget
  lines = [
    "Left: settings in three sections. Right: a dialog with Submit and Cancel.",
    "Up and Down move between rows; headers and the dimmed row are skipped.",
    "The line under the rows shows the help of the row with the keyboard.",
    "Space toggles, Left and Right move a choice or step a number.",
    "Enter or Space on 'Key bindings' or 'Reset' says Activated below.",
    "Shrink the terminal: the settings scroll and a scrollbar shows on the right.",
    "Submit with an empty name: the summary names it. Ctrl+Q leaves.",
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

# The settings form, built from a schema, with every row kind in it.
def settings : Widgets::Form
  form = Widgets::Form.new actions: false

  form.section "Display" do |section|
    section.toggle "motion", "Animate the panels", value: true,
      help: "Panels slide and fade. Off draws the end state at once."
    section.choice "bars", "Bar color", %w[gradient bands], value: "gradient",
      help: "Gradient shades by the fraction. Bands change at fixed points."
    section.choice "theme", "Theme",
      [{"dark", "Dark"}, {"light", "Light"}, {"contrast", "High contrast"}],
      value: "contrast", help: "A choice too wide for the row stacks its labels."
  end

  form.section "Input" do |section|
    section.toggle "mouse", "Mouse reporting", value: true
    section.number "wheel", "Cells per wheel notch", value: 3, range: 1..10, bar: true,
      help: "Left and Right step it. Digits and Enter set it."
    section.text "name", "Tester name", value: "anonymous",
      help: "Free text. Home and End move the cursor here."
    section.toggle "controls", "Controller support",
      help: "Not available on this terminal."
  end

  form.section "More" do |section|
    section.action "keys", "Key bindings", hint: "Enter to open",
      help: "An action row holds no value. It says Activated."
    section.action "reset", "Reset to defaults", hint: "Enter to reset"
  end

  form.enable "controls", false
  form.note "controls", "Forced off: no controller was found."
  form
end

# The dialog form, built by hand from fields, with buttons.
def dialog : Widgets::Form
  form = Widgets::Form.new width: Widgets::Layout::Sizing.fixed(DIALOG_WIDTH),
    height: Widgets::Layout::Sizing.fit
  form.add "name", Widgets::ValidatedField.new, [Widgets::Validators.required],
    help: "Required."
  form.add "port", Widgets::ValidatedField.new, [Widgets::Validators.numeric],
    help: "A number."
  form.toggle "tls", "Use TLS", value: true, help: "A schema row in a form with buttons."
  form
end

# The root of the tree, which writes down the last thing either form said.
class Session < Widgets::Panel
  # What the status line says.
  property status : Widgets::Label?

  def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
    said = case event
           when Widgets::Form::Changed   then "Changed #{event.key} to #{event.value.inspect}"
           when Widgets::Form::Activated then "Activated #{event.key}"
           when Widgets::Form::Submitted then "Submitted #{event.values}"
           when Widgets::Form::Invalid   then "Invalid #{event.errors}"
           when Widgets::Form::Cancelled then "Cancelled"
           end
    return unless said

    @status.try &.text=(said)
    context.consume
  end
end

TermBuf::Terminal.open do |terminal|
  accent = TermBuf::Style::DEFAULT.fg TermBuf::Color.rgb(120, 180, 250)

  left = Widgets::Panel.new direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow, height: Widgets::Layout::Sizing.grow,
    padding: Widgets::Layout::Padding.symmetric(horizontal: 1),
    border: Widgets::Border.rounded(title: " settings ", style: accent)
  left.focused_border_style = accent.bold
  left.add settings

  right = Widgets::Panel.new direction: Widgets::Layout::Direction::Column,
    height: Widgets::Layout::Sizing.grow,
    padding: Widgets::Layout::Padding.symmetric(horizontal: 1),
    border: Widgets::Border.rounded(title: " dialog ", style: accent)
  right.focused_border_style = accent.bold
  right.add dialog

  forms = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
    width: Widgets::Layout::Sizing.grow, height: Widgets::Layout::Sizing.grow, gap: 1
  forms.add left, right

  status = Widgets::Label.new "Nothing yet.", wrap: Widgets::Layout::Wrap::None
  status.width = Widgets::Layout::Sizing.grow

  root = Session.new(
    direction: Widgets::Layout::Direction::Column,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow)
  root.status = status
  root.add expected, forms, status

  leaving = false
  keymap = Widgets::App.default_keymap.merge(Widgets::Bindings.build do |map|
    map.bind TermBuf::Key.parse("Ctrl+Q"), "leave",
      ->(_context : Widgets::Context) { leaving = true; nil }
  end)

  app = Widgets::App.new terminal, root,
    TermBuf::Rect.full(terminal.size.columns, terminal.size.rows),
    terminal.events, terminal.policy, keymap

  # A click on a row presses it, and the wheel scrolls the settings.
  terminal.enable TermBuf::Tty::MOUSE_SGR
  terminal.hardware_cursor = terminal.cursor

  loop do
    app.frame { |spot| terminal.cursor.move_to spot[0], spot[1] if spot }
    terminal.paint

    break if leaving
    break unless app.wait
  end
end
