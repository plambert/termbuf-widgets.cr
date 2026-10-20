require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::Form do
  alias Form = TermBuf::Widgets::Form
  alias Field = TermBuf::Widgets::Field
  alias ValidatedField = TermBuf::Widgets::ValidatedField
  alias Validators = TermBuf::Widgets::Validators
  alias Log = Fixtures::MessageLog

  def rooted(form : Form) : Log
    root = Log.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    root.add form
    root
  end

  def app(root : Log, columns : Int32 = 30, rows : Int32 = 8) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  # A form of two fields, the first of which must be filled in and the second
  # of which must be a number.
  def two_fields : {Form, ValidatedField, ValidatedField}
    form = Form.new
    name = ValidatedField.new
    port = ValidatedField.new
    form.add "name", name, [Validators.required]
    form.add "port", port, [Validators.numeric]
    {form, name, port}
  end

  describe "building one" do
    it "puts the label beside the widget by default" do
      form, _, _ = two_fields
      entry = form.entry "name"

      expect(entry.try &.pair.direction.row?).to be_true
      expect(form.entries.map &.label).to eq %w[name port]
    end

    it "puts it above when it is asked to" do
      form = Form.new label_position: Form::LabelPosition::Above
      form.add "name", Field.new

      expect(form.entry("name").try &.pair.direction.column?).to be_true
    end

    it "squares the labels up against the longest" do
      form = Form.new
      form.add "name", Field.new
      form.add "hostname", Field.new
      Fixtures.render rooted(form), 30, 6

      widths = form.entries.map &.caption.rect.width
      expect(widths).to eq [8, 8]
    end

    it "gives the label column the width it was told to" do
      form = Form.new
      form.label_width = 12
      form.add "name", Field.new
      form.add "hostname", Field.new
      Fixtures.render rooted(form), 30, 6

      expect(form.entries.map &.caption.rect.width).to eq [12, 12]
    end

    it "draws the two buttons under the fields" do
      form, _, _ = two_fields

      expect(Fixtures.render(rooted(form), 30, 4)[2]).to contain "Submit"
      expect(form.submit_button.text).to eq "Submit"
      expect(form.cancel_button.text).to eq "Cancel"
    end
  end

  describe "tab order" do
    it "follows the order the fields were declared in, then the buttons" do
      form, name, port = two_fields
      made = app rooted(form)

      expect(made.focused).to be name

      Fixtures.presses made, "Tab"
      expect(made.focused).to be port

      Fixtures.presses made, "Tab"
      expect(made.focused).to be form.submit_button

      Fixtures.presses made, "Tab"
      expect(made.focused).to be form.cancel_button
    end
  end

  describe "handing it over" do
    it "collects a value per label and says so" do
      form, name, port = two_fields
      root = rooted form
      made = app root
      name.text = "yakko"
      port.text = "22"
      form.submit
      Fixtures.settle made
      handed = root.of(Form::Submitted)

      expect(handed.size).to eq 1
      expect(handed.first.values).to eq({"name" => "yakko", "port" => "22"})
      expect(root.of(Form::Invalid)).to be_empty
    end

    it "is handed over by the Submit button" do
      form, name, port = two_fields
      root = rooted form
      made = app root
      name.text = "yakko"
      port.text = "22"
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Enter"

      expect(root.of(Form::Submitted).size).to eq 1
    end

    it "takes in what a TextArea holds too" do
      form = Form.new
      area = TermBuf::Widgets::TextArea.new
      form.add "notes", area
      root = rooted form
      made = app root
      area.text = "two words"
      form.submit
      Fixtures.settle made

      expect(root.of(Form::Submitted).first.values).to eq({"notes" => "two words"})
    end

    it "asks the hook about a widget it does not know" do
      form = Form.new
      box = TermBuf::Widgets::Checkbox.new "wrap", checked: true
      form.add "wrap", box
      form.value_of = ->(widget : TermBuf::Widgets::Widget) do
        found = widget.as? TermBuf::Widgets::Checkbox
        found ? (found.checked? ? "yes" : "no") : nil
      end
      root = rooted form
      made = app root
      form.submit
      Fixtures.settle made

      expect(root.of(Form::Submitted).first.values).to eq({"wrap" => "yes"})
    end
  end

  describe "what the rules refuse" do
    it "gathers every message by label and says nothing was submitted" do
      form, _, port = two_fields
      root = rooted form
      made = app root
      port.text = "abc"
      form.submit
      Fixtures.settle made
      refusals = root.of(Form::Invalid)

      expect(refusals.size).to eq 1
      expect(refusals.first.errors).to eq({"name" => ["required"], "port" => ["a number"]})
      expect(root.of(Form::Submitted)).to be_empty
    end

    it "puts the keyboard on the first field that was refused" do
      form, name, port = two_fields
      root = rooted form
      made = app root
      name.text = "yakko"
      port.text = "abc"
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Enter"

      expect(made.focused).to be port
    end

    it "asks a validated field's own rules as well as the form's" do
      form = Form.new
      field = ValidatedField.new
      field.validators << Validators.length(min: 4)
      form.add "word", field
      root = rooted form
      made = app root
      field.text = "ab"
      form.submit
      Fixtures.settle made

      expect(root.of(Form::Invalid).first.errors).to eq({"word" => ["at least 4 characters"]})
    end

    it "asks its own rules about every value at once" do
      form = Form.new
      first = Field.new
      second = Field.new
      form.add "from", first
      form.add "to", second
      form.rules << ->(values : Hash(String, String)) do
        values["from"] < values["to"] ? nil : "to comes after from"
      end
      root = rooted form
      made = app root
      first.text = "9"
      second.text = "3"
      form.submit
      Fixtures.settle made
      refusals = root.of(Form::Invalid)

      expect(refusals.first.errors).to eq({Form::WHOLE => ["to comes after from"]})
      expect(refusals.first.first_field).to be_nil
    end

    it "draws a line naming what was refused" do
      form, _, port = two_fields
      made = app rooted(form)
      port.text = "abc"
      form.submit
      Fixtures.settle made

      expect(Fixtures.frame(made)[2]).to eq "name: required; port: a number"
    end

    it "draws no line at all when it is told not to" do
      form = Form.new summary: false
      field = ValidatedField.new
      form.add "name", field, [Validators.required]
      made = app rooted(form)
      form.submit
      Fixtures.settle made

      expect(Fixtures.frame(made)[1]).not_to contain "required"
    end

    it "takes the line away once the form passes" do
      form, name, port = two_fields
      made = app rooted(form)
      port.text = "abc"
      form.submit
      Fixtures.settle made
      name.text = "yakko"
      port.text = "22"
      form.submit
      Fixtures.settle made

      expect(form.errors).to be_empty
      expect(Fixtures.frame(made)[2]).to contain "Submit"
    end
  end

  describe "Enter in a field" do
    it "hands the whole form over" do
      form, name, port = two_fields
      root = rooted form
      made = app root
      name.text = "yakko"
      port.text = "22"
      Fixtures.presses made, "Enter"

      expect(root.of(Form::Submitted).size).to eq 1
    end

    it "leaves the line in the field it was typed into" do
      form, name, port = two_fields
      root = rooted form
      made = app root
      port.text = "22"
      Fixtures.type made, "yakko"
      Fixtures.presses made, "Enter"

      expect(name.text).to eq "yakko"
      expect(root.of(Form::Submitted).first.values).to eq({"name" => "yakko", "port" => "22"})
    end

    it "hands it over even when the line itself was refused" do
      form, _, port = two_fields
      root = rooted form
      made = app root
      port.text = "abc"
      Fixtures.presses made, "Enter"

      expect(root.of(Form::Invalid).size).to eq 1
    end

    it "does nothing when it is told not to" do
      form = Form.new submit_on_enter: false
      field = Field.new
      form.add "name", field
      root = rooted form
      made = app root
      Fixtures.type made, "yakko"
      Fixtures.presses made, "Enter"

      expect(root.of(Form::Submitted)).to be_empty
      expect(field.text).to eq "yakko"
    end
  end

  describe "giving up" do
    it "says so when the Cancel button is pressed" do
      form, _, _ = two_fields
      root = rooted form
      made = app root
      3.times { Fixtures.presses made, "Tab" }
      Fixtures.presses made, "Enter"

      expect(made.focused).to be form.cancel_button
      expect(root.of(Form::Cancelled).size).to eq 1
      expect(root.of(Form::Submitted)).to be_empty
    end
  end

  # A form of every schema kind but color, in two sections, with no buttons.
  def settings : Form
    form = Form.new actions: false
    form.section "Display" do |section|
      section.toggle "motion", "Animate", value: true, help: "Panels slide."
      section.choice "bars", "Bars", %w[gradient bands], value: "gradient"
    end
    form.section "Input" do |section|
      section.number "wheel", "Wheel", value: 3, range: 1..10
      section.text "name", "Name", value: "anon"
      section.action "keys", "Keys", hint: "Enter to open", help: "Lists the keys."
    end
    form
  end

  def changes(root : Log) : Array({String, Form::Value})
    root.of(Form::Changed).map { |change| {change.key, change.value} }
  end

  # A form of *count* toggles in one section, to be taller than its window.
  def tall(count : Int32) : {Form, Array(TermBuf::Widgets::Checkbox)}
    form = Form.new actions: false
    boxes = [] of TermBuf::Widgets::Checkbox
    form.section "Many" do |section|
      count.times { |index| boxes << section.toggle("row#{index}", "Row #{index}").input }
    end
    {form, boxes}
  end

  # Whether *widget* sits wholly inside the window of *form*.
  def in_view?(form : Form, widget : TermBuf::Widgets::Widget) : Bool
    window = form.fields.content
    box = widget.rect
    box.y >= window.y && box.y + box.height <= window.y + window.height
  end

  describe "a schema" do
    it "builds the rows in order, with their sections" do
      form = settings

      expect(form.rows.map &.key).to eq %w[motion bars wheel name keys]
      expect(form.sections.compact_map &.name).to eq %w[Display Input]
    end

    it "draws a header for each section and a blank line between them" do
      made = app rooted(settings), 40, 10

      expect(Fixtures.frame(made)).to eq [
        "Display",
        "Animate ☑",
        "Bars    (•) gradient  ( ) bands",
        "",
        "Input",
        "Wheel   3",
        "Name    anon",
        "Keys    Enter to open",
        "Panels slide.",
        "",
      ]
    end

    it "puts rows given outside any section in an unnamed one at the top" do
      form = settings
      form.toggle "first", "First"

      expect(form.rows.map(&.key).first).to eq "first"
      expect(Fixtures.render(rooted(form), 40, 12)[0]).to eq "First   ☐"
    end

    it "refuses a key it already has" do
      form = settings

      expect { form.toggle "motion", "Again" }.to raise_error(ArgumentError)
    end

    it "takes a choice as values and labels" do
      form = Form.new actions: false
      form.choice "size", "Size", [{"s", "Small"}, {"l", "Large"}], value: "l"

      expect(form["size"]).to eq "l"
      expect(Fixtures.render(rooted(form), 40, 2)[0]).to eq "Size ( ) Small  (•) Large"
    end

    it "has no buttons and no submit on Enter when built without actions" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      4.times { Fixtures.presses made, "Down" }
      Fixtures.presses made, "Enter"

      expect(form.actions?).to be_false
      expect(form.submit_on_enter?).to be_false
      expect(root.of(Form::Submitted)).to be_empty
    end
  end

  describe "the values" do
    it "answers each row's value by key, typed, with no entry for an action" do
      expect(settings.values).to eq({"motion" => true, "bars" => "gradient", "wheel" => 3,
                                     "name" => "anon"} of String => Form::Value)
    end

    it "answers them as text for the submit path" do
      expect(settings.texts).to eq({"motion" => "true", "bars" => "gradient", "wheel" => "3",
                                    "name" => "anon"})
    end

    it "reads and sets one by key, and sends nothing for a value set" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      form["motion"] = false
      form["bars"] = "bands"
      form["wheel"] = 7
      form["name"] = "yakko"
      Fixtures.settle made

      expect(form["motion"]).to eq false
      expect(form["wheel"]).to eq 7
      expect(form["keys"]).to be_nil
      expect(root.of(Form::Changed)).to be_empty
      expect(Fixtures.frame(made)[2]).to eq "Bars    ( ) gradient  (•) bands"
    end

    it "refuses a value of the wrong kind" do
      form = settings

      expect { form["motion"] = "yes" }.to raise_error(ArgumentError)
      expect { form["nothing"] = true }.to raise_error(KeyError)
    end

    it "hands the schema rows over as text in a form with buttons" do
      form = Form.new
      form.toggle "wrap", "Wrap", value: true
      form.add "name", Field.new
      root = rooted form
      made = app root
      form.submit
      Fixtures.settle made

      expect(root.of(Form::Submitted).first.values).to eq({"wrap" => "true", "name" => ""})
    end
  end

  describe "a change" do
    it "is heard in the same pump as the key that made it" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      Fixtures.press made, "Space"

      expect(changes root).to eq [{"motion", false}] of {String, Form::Value}
    end

    it "is heard in the same wait as the key that made it" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      made.events.send TermBuf::Events::Key.new(TermBuf::Key.parse_one("Space"), Bytes.empty)
      made.wait

      expect(changes root).to eq [{"motion", false}] of {String, Form::Value}
    end
  end

  describe "each kind" do
    it "toggles on Space and says so" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      Fixtures.presses made, "Space"

      expect(changes root).to eq [{"motion", false}]
      expect(Fixtures.frame(made)[1]).to eq "Animate ☐"
    end

    it "moves an inline choice on Left and Right and says so" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Right"
      Fixtures.presses made, "Right"
      Fixtures.presses made, "Left"

      expect(changes root).to eq [{"bars", "bands"}, {"bars", "gradient"}]
    end

    it "takes the label clicked in a choice" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      Fixtures.click made, 24, 2

      expect(changes root).to eq [{"bars", "bands"}]
      expect(form.focused_row.try &.key).to eq "bars"
    end

    it "stacks a choice whose labels do not fit on one line" do
      form = Form.new actions: false, label_position: Form::LabelPosition::Left
      form.choice "bars", "Bars", %w[gradient bands], value: "bands"

      expect(Fixtures.render(rooted(form), 20, 3)).to eq ["Bars ( ) gradient", "     (•) bands", ""]
    end

    it "steps a number on Left and Right and says so" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      2.times { Fixtures.presses made, "Down" }
      Fixtures.presses made, "Right"
      Fixtures.presses made, "Right"
      Fixtures.presses made, "Left"

      expect(changes root).to eq [{"wheel", 4}, {"wheel", 5}, {"wheel", 4}]
    end

    it "takes a typed number when the keyboard leaves the row" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      2.times { Fixtures.presses made, "Down" }
      Fixtures.presses made, "Backspace"
      Fixtures.type made, "9"
      Fixtures.presses made, "Down"
      Fixtures.settle made

      expect(form["wheel"]).to eq 9
      expect(changes(root).last).to eq({"wheel", 9})
    end

    it "says what a text row holds at every key" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      3.times { Fixtures.presses made, "Down" }
      Fixtures.type made, "y"
      Fixtures.settle made
      Fixtures.presses made, "Backspace"

      expect(changes root).to eq [{"name", "anony"}, {"name", "anon"}]
    end

    it "leaves Home and End to a text row's cursor" do
      form = settings
      made = app rooted(form), 40, 10
      3.times { Fixtures.presses made, "Down" }
      Fixtures.presses made, "Home"
      Fixtures.type made, "x"
      Fixtures.settle made

      expect(form["name"]).to eq "xanon"
      expect(form.focused_row.try &.key).to eq "name"
    end

    it "keeps the line in a text row on Enter" do
      form = settings
      made = app rooted(form), 40, 10
      3.times { Fixtures.presses made, "Down" }
      Fixtures.presses made, "Enter"

      expect(form["name"]).to eq "anon"
    end

    it "activates an action row on Enter, Space and a click, with its key" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      4.times { Fixtures.presses made, "Down" }
      Fixtures.presses made, "Enter"
      Fixtures.presses made, "Space"
      Fixtures.click made, 10, 7
      Fixtures.click made, 1, 7

      expect(root.of(Form::Activated).map &.key).to eq %w[keys keys keys keys]
      expect(form.values.has_key?("keys")).to be_false
    end

    it "toggles a row whose label is clicked" do
      form = settings
      root = rooted form
      made = app root, 40, 10
      Fixtures.presses made, "Down"
      Fixtures.click made, 1, 1

      expect(changes root).to eq [{"motion", false}]
      expect(form.focused_row.try &.key).to eq "motion"
    end
  end

  describe "typing at a row" do
    # *form* with `j` and `k` bound on its own keymap to move between rows.
    def lettered(form : Form) : Form
      letters = TermBuf::Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("j"), "the row below",
          ->(context : TermBuf::Widgets::Context) { form.step_row 1, context }
        map.bind TermBuf::Key.parse("k"), "the row above",
          ->(context : TermBuf::Widgets::Context) { form.step_row(-1, context) }
      end
      form.keymap = Form.row_keys(form).merge letters
      form
    end

    it "says whether the row with the keyboard takes free text" do
      form = settings
      made = app rooted(form), 40, 10
      seen = [] of Bool

      4.times do
        seen << form.typing?
        Fixtures.presses made, "Down"
      end
      seen << form.typing?

      expect(seen).to eq [false, false, false, true, false]
    end

    it "takes digits on a number row and every printable key on a text row" do
      form = settings
      made = app rooted(form), 40, 10
      2.times { Fixtures.presses made, "Down" }
      digit = TermBuf::Key.parse_one "5"
      letter = TermBuf::Key.parse_one "j"
      on_number = {form.types?(digit), form.types?(letter)}
      Fixtures.presses made, "Down"

      expect(on_number).to eq({true, false})
      expect({form.types?(digit), form.types?(letter)}).to eq({true, true})
      expect(form.types?(TermBuf::Key.parse_one("Ctrl+j"))).to be_false
    end

    it "lets a printable key bound on the form through to a text row" do
      form = lettered settings
      made = app rooted(form), 40, 10
      3.times { Fixtures.presses made, "Down" }
      Fixtures.press made, "End"
      Fixtures.type made, "jk"

      expect(form["name"]).to eq "anonjk"
      expect(form.focused_row.try &.key).to eq "name"
    end

    it "still fires that binding on a row that does not take text" do
      form = lettered settings
      made = app rooted(form), 40, 10
      Fixtures.type made, "jj"

      expect(form.focused_row.try &.key).to eq "wheel"
    end

    it "hands a key to a text row for a host binding that asks #type" do
      form = settings
      root = rooted form
      moved = 0
      root.keymap = TermBuf::Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("j"), "the row below",
          ->(context : TermBuf::Widgets::Context) { moved += 1 unless form.type context; nil }
      end
      made = app root, 40, 10
      Fixtures.type made, "j"
      3.times { Fixtures.presses made, "Down" }
      Fixtures.type made, "j"

      expect(moved).to eq 1
      expect(changes root).to eq [{"name", "anonj"}] of {String, Form::Value}
    end
  end

  describe "moving between rows" do
    it "moves down and up, skipping headers and stopping at the ends" do
      form = settings
      made = app rooted(form), 40, 10
      keys = [] of String?

      6.times do
        keys << form.focused_row.try &.key
        Fixtures.presses made, "Down"
      end
      keys << form.focused_row.try &.key
      Fixtures.presses made, "Up"
      keys << form.focused_row.try &.key

      expect(keys).to eq %w[motion bars wheel name keys keys keys name]
    end

    it "goes to the first and last row on Home and End" do
      form = settings
      made = app rooted(form), 40, 10
      Fixtures.presses made, "End"
      expect(form.focused_row.try &.key).to eq "keys"

      Fixtures.presses made, "Home"
      expect(form.focused_row.try &.key).to eq "motion"
    end

    it "moves through the focus ring on Tab" do
      form = settings
      made = app rooted(form), 40, 10
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Tab"
      expect(form.focused_row.try &.key).to eq "wheel"

      Fixtures.presses made, "Shift+Tab"
      expect(form.focused_row.try &.key).to eq "bars"
    end

    it "goes from the buttons back to the last row on Up" do
      form = Form.new
      form.toggle "one", "One"
      form.toggle "two", "Two"
      made = app rooted(form), 30, 6
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Tab"
      expect(made.focused).to be form.submit_button

      Fixtures.presses made, "Up"
      expect(form.focused_row.try &.key).to eq "two"
    end

    it "shows the help of the row with the keyboard" do
      form = settings
      made = app rooted(form), 40, 10
      expect(Fixtures.frame(made)[8]).to eq "Panels slide."

      Fixtures.presses made, "Down"
      expect(Fixtures.frame(made)[8]).to eq ""

      Fixtures.presses made, "End"
      expect(Fixtures.frame(made)[8]).to eq "Lists the keys."
    end

    it "shows a note under the help" do
      form = settings
      form.note "motion", "Set by the server."
      made = app rooted(form), 40, 11

      expect(Fixtures.frame(made)[8..9]).to eq ["Panels slide.", "Set by the server."]
    end

    it "leaves the help line out when no row has help" do
      form = Form.new actions: false
      form.toggle "one", "One"
      form.toggle "two", "Two"

      expect(Fixtures.render(rooted(form), 30, 3)).to eq ["One ☐", "Two ☐", ""]
    end
  end

  describe "a form taller than its window" do
    it "scrolls the row with the keyboard into view on every move down" do
      form, boxes = tall 12
      made = app rooted(form), 30, 6

      11.times do
        Fixtures.presses made, "Down"
        made.frame
        held = made.focused
        expect(held && in_view?(form, held)).to be_true
      end
      expect(made.focused).to be boxes.last
    end

    it "scrolls it into view on every move back up" do
      form, boxes = tall 12
      made = app rooted(form), 30, 6
      Fixtures.presses made, "End"
      made.frame

      11.times do
        Fixtures.presses made, "Up"
        made.frame
        held = made.focused
        expect(held && in_view?(form, held)).to be_true
      end
      expect(made.focused).to be boxes.first
      expect(form.fields.scroll_y).to eq 0
    end

    it "keeps a row of margin past the row with the keyboard" do
      form, boxes = tall 12
      made = app rooted(form), 30, 6
      3.times { Fixtures.presses made, "Down" }
      made.frame

      expect(boxes[4].rect.y).to be < form.fields.content.y + form.fields.content.height
    end

    it "lands on the last row on PageDown from the last page" do
      form, boxes = tall 12
      made = app rooted(form), 30, 6
      4.times do
        Fixtures.presses made, "PageDown"
        made.frame
      end

      expect(made.focused).to be boxes.last
      expect(in_view?(form, boxes.last)).to be_true
    end

    it "moves a window's worth on PageDown and back on PageUp" do
      form, boxes = tall 12
      made = app rooted(form), 30, 6
      Fixtures.presses made, "PageDown"
      made.frame
      landed = boxes.index(&.same?(made.focused)) || 0

      expect(landed).to be > 1
      expect(made.focused.try { |held| in_view?(form, held) }).to be_true

      Fixtures.presses made, "PageUp"
      made.frame
      expect(made.focused).to be boxes.first
    end

    it "draws the scrollbar only while the rows overflow" do
      form, _ = tall 12
      made = app rooted(form), 30, 6
      lines = Fixtures.frame(made)

      expect(lines[0][29]?).to eq '█'

      short, _ = tall 2
      expect(Fixtures.render(rooted(short), 30, 6).none? &.includes?('│')).to be_true
    end

    it "scrolls on the wheel" do
      form, _ = tall 12
      made = app rooted(form), 30, 6
      Fixtures.mouse made, TermBuf::Input::Mouse::Action::Press, 2, 2,
        TermBuf::Input::Mouse::Button::WheelDown

      expect(form.fields.scroll_y).to eq 3
    end

    it "keeps its buttons on the screen" do
      form = Form.new
      8.times { |index| form.toggle "row#{index}", "Row #{index}" }
      lines = Fixtures.render rooted(form), 30, 5

      expect(lines[4]).to contain "Submit"
    end

    it "is as tall as its rows when it is told to fit" do
      form, _ = tall 3
      form.height = Sizing.fit
      Fixtures.render rooted(form), 30, 10

      expect(form.rect.height).to eq 4
    end
  end

  describe "a narrow form" do
    it "puts the labels above the inputs" do
      form = Form.new actions: false
      form.toggle "motion", "Animate"
      form.text "name", "Name", value: "anon"
      made = app rooted(form), 16, 5

      expect(Fixtures.frame(made)).to eq ["Animate", "☐", "Name", "anon", ""]
    end

    it "stays inside its parent when a label is wider than the form" do
      form = Form.new actions: false
      form.choice "bars", "Bar color for the panels", %w[gradient bands], value: "bands"
      lines = Fixtures.render rooted(form), 16, 4

      expect(form.rect.width).to eq 16
      expect(lines).to eq ["Bar color for t", "( ) gradient", "(•) bands", ""]
    end

    it "puts them beside again when it is wide enough" do
      form = Form.new actions: false
      form.toggle "motion", "Animate"
      made = app rooted(form), 16, 3
      made.resized 30, 3
      made.pump

      expect(Fixtures.frame(made)[0]).to eq "Animate ☐"
    end

    it "keeps them beside when it is told to" do
      form = Form.new actions: false, label_position: Form::LabelPosition::Left
      form.toggle "motion", "Animate"

      expect(Fixtures.render(rooted(form), 16, 2)[0]).to eq "Animate ☐"
    end
  end

  describe "a disabled row" do
    it "is skipped by the keyboard" do
      form = settings
      form.enable "bars", false
      made = app rooted(form), 40, 10
      Fixtures.presses made, "Down"

      expect(form.focused_row.try &.key).to eq "wheel"
    end

    it "is skipped by Tab" do
      form = settings
      form.enable "bars", false
      made = app rooted(form), 40, 10
      Fixtures.presses made, "Tab"

      expect(form.focused_row.try &.key).to eq "wheel"
    end

    it "is dimmed" do
      form = settings
      form.enable "name", false
      buffer = Fixtures.painted rooted(form), 40, 10

      expect(Fixtures.style_at(buffer, 0, 6).attributes.faint?).to be_true
      expect(Fixtures.style_at(buffer, 8, 6).attributes.faint?).to be_true
      expect(Fixtures.style_at(buffer, 0, 5).attributes.faint?).to be_false
    end

    it "takes the keyboard again once it is enabled" do
      form = settings
      form.enable "bars", false
      form.enable "bars", true
      made = app rooted(form), 40, 10
      Fixtures.presses made, "Down"

      expect(form.focused_row.try &.key).to eq "bars"
    end
  end

  describe "the marks" do
    it "spells a choice in ASCII where its dot measures two cells" do
      wide = TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2
      form = Form.new actions: false
      form.toggle "motion", "Animate", value: true
      form.choice "bars", "Bars", %w[gradient bands]

      expect(Fixtures.render(rooted(form), 40, 2, wide)).to eq [
        "Animate ☑",
        "Bars    (*) gradient  ( ) bands",
      ]
    end
  end

  describe "a color row" do
    alias Color = TermBuf::Color
    alias Depth = TermBuf::Widgets::Depth

    def colored(depth : Depth = Depth::TrueColor) : Form
      form = Form.new actions: false, depth: depth
      form.color "accent", "Accent", Color.rgb(0, 0, 0), help: "The color of the edges."
      form.toggle "motion", "Animate"
      form
    end

    def color_row(form : Form) : Form::ColorRow
      form.row("accent").as(Form::ColorRow)
    end

    def attached(form : Form, rows : Int32 = 16) : {Log, Fixtures::TestApp}
      root = rooted form
      made = app root, 80, rows
      form.attach made
      {root, made}
    end

    it "shows a swatch with the color's value" do
      form = Form.new actions: false
      form.color "accent", "Accent", Color.rgb(0x3080C0)

      expect(Fixtures.render(rooted(form), 30, 1)[0]).to end_with "#3080c0"
      expect(form["accent"]).to eq Color.rgb(0x3080C0)
      expect(form.texts["accent"]).to eq "#3080c0"
    end

    it "opens the picker in a popover on Enter, on the row's color" do
      form = colored
      _, made = attached form
      row = color_row form
      Fixtures.presses made, "Enter"

      expect(row.open?).to be_true
      expect(row.popover.try &.open?).to be_true
      expect(made.focused.same?(row.picker.grid)).to be_true
      expect(row.picker.value).to eq Color.rgb(0, 0, 0)
    end

    it "opens it on Space as well" do
      form = colored
      _, made = attached form
      Fixtures.presses made, "Space"

      expect(color_row(form).open?).to be_true
    end

    it "takes a color with Enter on the grid, closes, and says Changed" do
      form = colored
      root, made = attached form
      row = color_row form
      Fixtures.presses made, "Enter Right Enter"
      Fixtures.settle made

      expect(row.open?).to be_false
      expect(made.focused.same?(row.input)).to be_true
      expect(form["accent"]).to eq Color.rgb(0, 0, 95)
      expect(row.input.color).to eq Color.rgb(0, 0, 95)
      expect(changes root).to eq [{"accent", Color.rgb(0, 0, 95).as(Form::Value)}]
    end

    it "applies each change while the picker is open" do
      form = colored
      root, made = attached form
      Fixtures.presses made, "Enter Tab Ctrl+U"
      Fixtures.type made, "200"
      Fixtures.settle made

      expect(color_row(form).open?).to be_true
      expect(form["accent"]).to eq Color.rgb(200, 0, 0)
      expect(changes(root).map &.[1]).to eq [Color.rgb(2, 0, 0), Color.rgb(20, 0, 0),
                                             Color.rgb(200, 0, 0)]
    end

    it "leaves the value alone on Escape" do
      form = colored
      root, made = attached form
      row = color_row form
      Fixtures.presses made, "Enter Right Escape"
      Fixtures.settle made

      expect(row.open?).to be_false
      expect(made.focused.same?(row.input)).to be_true
      expect(form["accent"]).to eq Color.rgb(0, 0, 0)
      expect(changes root).to be_empty
    end

    it "puts back the color it opened on when Escape follows a change" do
      form = colored
      root, made = attached form
      Fixtures.presses made, "Enter Right Space"
      Fixtures.settle made
      expect(form["accent"]).to eq Color.rgb(0, 0, 95)

      Fixtures.presses made, "Escape"
      Fixtures.settle made
      expect(form["accent"]).to eq Color.rgb(0, 0, 0)
      expect(color_row(form).input.color).to eq Color.rgb(0, 0, 0)
      expect(changes(root).map &.[1]).to eq [Color.rgb(0, 0, 95), Color.rgb(0, 0, 0)]
    end

    it "puts back the color with Escape from a field" do
      form = colored
      _, made = attached form
      Fixtures.presses made, "Enter Tab Ctrl+U"
      Fixtures.type made, "200"
      Fixtures.presses made, "Escape"
      Fixtures.settle made

      expect(color_row(form).open?).to be_false
      expect(form["accent"]).to eq Color.rgb(0, 0, 0)
    end

    it "keeps the color when a click outside closes the popover" do
      form = colored
      _, made = attached form
      Fixtures.presses made, "Enter Right Space"
      Fixtures.settle made
      Fixtures.click made, 79, 15
      Fixtures.settle made

      expect(color_row(form).open?).to be_false
      expect(form["accent"]).to eq Color.rgb(0, 0, 95)
    end

    it "opens in a dialog when the popover fits neither under nor over the row" do
      form = Form.new actions: false
      6.times { |index| form.toggle "t#{index}", "Toggle #{index}" }
      form.color "accent", "Accent", Color.rgb(0, 0, 0)
      root, made = attached form, 18
      row = color_row form
      Fixtures.presses made, "End Enter"

      expect(row.popover.try &.open?).to be_false
      expect(row.dialog.try &.open?).to be_true
      expect(made.focused.same?(row.picker.grid)).to be_true

      Fixtures.presses made, "Right Enter"
      Fixtures.settle made
      expect(row.open?).to be_false
      expect(form["accent"]).to eq Color.rgb(0, 0, 95)
      expect(changes(root).size).to eq 1
    end

    it "leaves the grid out of a dialog on a short screen, and closes on Enter in a field" do
      form = colored
      _, made = attached form, 10
      row = color_row form
      Fixtures.presses made, "Enter"

      expect(row.dialog.try &.open?).to be_true
      expect(row.picker.grid.shown?).to be_false
      expect(made.focused.same?(row.picker.red)).to be_true

      Fixtures.presses made, "Ctrl+U"
      Fixtures.type made, "200"
      Fixtures.presses made, "Enter"
      Fixtures.settle made
      expect(row.open?).to be_false
      expect(form["accent"]).to eq Color.rgb(200, 0, 0)
    end

    it "closes on Enter in a field and keeps what was typed, held to the range" do
      form = colored
      _, made = attached form
      Fixtures.presses made, "Enter Tab Ctrl+U"
      Fixtures.type made, "300"
      Fixtures.presses made, "Enter"
      Fixtures.settle made

      expect(color_row(form).open?).to be_false
      expect(form["accent"]).to eq Color.rgb(255, 0, 0)
    end

    it "closes on Enter in the hex field and keeps the color" do
      form = colored
      _, made = attached form
      Fixtures.presses made, "Enter Tab Tab Tab Tab Ctrl+U"
      Fixtures.type made, "3080c0"
      Fixtures.presses made, "Enter"
      Fixtures.settle made

      expect(color_row(form).open?).to be_false
      expect(form["accent"]).to eq Color.rgb(0x3080C0)
    end

    it "keeps the dialog's own message to itself" do
      form = colored
      root, made = attached form, 10
      row = color_row form
      Fixtures.presses made, "Enter"
      row.dialog.try &.buttons.first.press
      Fixtures.settle made

      expect(row.open?).to be_false
      expect(root.of(TermBuf::Widgets::Dialog::Closed)).to be_empty
    end

    it "does nothing on Enter until the form is given the application" do
      form = colored
      made = app rooted(form), 80, 16
      Fixtures.presses made, "Enter"

      expect(color_row(form).open?).to be_false
    end

    it "offers the form's depth unless the row names its own" do
      form = colored Depth::Indexed256
      form.color "edge", "Edge", Color.rgb(0x3080C0), depth: Depth::TrueColor
      row = color_row form

      expect(row.depth).to eq Depth::Indexed256
      expect(row.input.value_text).to eq "#000000 16"
      expect(row.picker.depth).to eq Depth::Indexed256
      expect(form.row("edge").as(Form::ColorRow).depth).to eq Depth::TrueColor

      form.depth = Depth::TrueColor
      expect(row.input.value_text).to eq "#000000"
      expect(row.picker.depth).to eq Depth::TrueColor
    end

    it "refuses a value that is not a color" do
      form = colored

      expect { form["accent"] = "red" }.to raise_error(ArgumentError)
    end
  end
end
