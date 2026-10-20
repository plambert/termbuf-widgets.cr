require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::ColorPicker do
  alias ColorPicker = TermBuf::Widgets::ColorPicker
  alias Depth = TermBuf::Widgets::Depth
  alias Color = TermBuf::Color
  alias Log = Fixtures::MessageLog

  def rooted(picker : ColorPicker) : Log
    root = Log.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    root.add picker
    root
  end

  def app(root : Log, columns : Int32 = 80, rows : Int32 = 12) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  def fields(picker : ColorPicker) : Array(String)
    [picker.red.text, picker.green.text, picker.blue.text, picker.hex.text]
  end

  def changes(root : Log) : Array(Color)
    root.of(ColorPicker::Changed).map &.color
  end

  describe "what it draws" do
    it "puts the swatch on top, the grid under it and the fields last" do
      picker = ColorPicker.new Color.rgb(0x3080C0)
      lines = Fixtures.render rooted(picker), 80, 12

      expect(lines[0]).to end_with "#3080c0"
      expect(lines[8]).to start_with "R 48"
      expect(lines[8]).to contain "G 128"
      expect(lines[8]).to contain "B 192"
      expect(lines[9]).to eq "Hex #3080c0"
    end

    it "is 72 columns by 7 rows of grid in true color, with square cells" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      buffer = Fixtures.painted rooted(picker), 80, 12

      expect(picker.grid.rect.width).to eq 72
      expect(picker.grid.rect.height).to eq 7
      expect(Fixtures.style_at(buffer, 0, 1).background).to eq Color.rgb(0, 0, 0)
      expect(Fixtures.style_at(buffer, 1, 1).background).to eq Color.rgb(0, 0, 0)
      expect(Fixtures.style_at(buffer, 2, 1).background).to eq Color.rgb(0, 0, 95)
      expect(Fixtures.style_at(buffer, 12, 1).background).to eq Color.rgb(95, 0, 0)
      expect(Fixtures.style_at(buffer, 0, 7).background).to eq Color.rgb(8, 8, 8)
    end

    it "adds the sixteen system colors on top at 256 colors, every cell indexed" do
      picker = ColorPicker.new Color.indexed(16), depth: Depth::Indexed256
      buffer = Fixtures.painted rooted(picker), 80, 12

      expect(picker.grid.rect.height).to eq 8
      expect(Fixtures.style_at(buffer, 2, 1).background).to eq Color.indexed(1)
      expect(Fixtures.style_at(buffer, 2, 2).background).to eq Color.indexed(17)
      expect(Fixtures.style_at(buffer, 0, 8).background).to eq Color.indexed(232)
    end

    it "shows the index under the cursor beside the hex at 256 colors" do
      picker = ColorPicker.new Color.indexed(208), depth: Depth::Indexed256
      lines = Fixtures.render rooted(picker), 80, 12

      expect(lines[0]).to end_with "#ff8700 208"
    end

    it "draws one-column cells when there is no room for two" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      buffer = Fixtures.painted rooted(picker), 50, 12

      expect(picker.grid.rect.width).to eq 50
      expect(Fixtures.style_at(buffer, 1, 1).background).to eq Color.rgb(0, 0, 95)
    end

    it "leaves the grid out on a short screen and keeps the swatch and the fields" do
      picker = ColorPicker.new Color.rgb(0x3080C0)
      made = app rooted(picker), 80, 4
      lines = made.lines

      expect(picker.min_height).to eq 3
      expect(picker.grid.shown?).to be_false
      expect(lines[0]).to end_with "#3080c0"
      expect(lines.any? &.starts_with?("Hex #3080c0")).to be_true
      expect(made.focused).to be picker.red

      Fixtures.presses made, "Shift+Tab"
      expect(made.focused).to be picker.hex
    end
  end

  describe "the grid" do
    it "moves with the arrows and takes a color with Enter, and the fields follow" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      root = rooted picker
      made = app root
      expect(made.focused).to be picker.grid

      Fixtures.presses made, "Right Right Down"
      expect(picker.value).to eq Color.rgb(0, 0, 0)

      Fixtures.presses made, "Enter"
      expect(picker.value).to eq Color.rgb(0, 95, 135)
      expect(fields picker).to eq ["0", "95", "135", "#005f87"]
      expect(picker.swatch.color).to eq Color.rgb(0, 95, 135)
      expect(changes root).to eq [Color.rgb(0, 95, 135)]
    end

    it "takes a color with Space" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Down Space"

      expect(picker.value).to eq Color.rgb(0, 95, 0)
    end

    it "takes the color clicked" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      root = rooted picker
      made = app root
      Fixtures.presses made, "Tab"
      Fixtures.click made, 10, 2

      expect(made.focused).to be picker.grid
      expect(picker.value).to eq Color.rgb(0, 95, 255)
      expect(changes root).to eq [Color.rgb(0, 95, 255)]
    end

    it "marks the cell under the cursor while it has the keyboard" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)

      expect(made.lines[1]).to start_with "[]"
      Fixtures.presses made, "Right"
      expect(Fixtures.frame(made)[1]).to start_with "  []"
    end

    it "puts the cursor on the value's cell" do
      picker = ColorPicker.new Color.rgb(95, 135, 175)

      expect(picker.grid.current.color).to eq Color.rgb(95, 135, 175)
    end

    it "offers a default cell at the end of the grey row when it has one" do
      picker = ColorPicker.new Color.rgb(0, 0, 0), reset_to: Color.rgb(0xC0C0C0)
      root = rooted picker
      made = app root
      expect(made.lines[7]).to contain "default"

      Fixtures.presses made, "Down Down Down Down Down Down"
      Fixtures.presses made, ("Right " * 30).strip
      Fixtures.presses made, "Enter"

      expect(picker.value).to eq Color.rgb(0xC0C0C0)
      expect(fields picker).to eq ["192", "192", "192", "#c0c0c0"]
    end
  end

  describe "the fields" do
    it "moves the swatch and the other fields on a channel edit" do
      picker = ColorPicker.new Color.rgb(0, 95, 135)
      root = rooted picker
      made = app root
      Fixtures.presses made, "Tab Ctrl+U"
      Fixtures.type made, "200"
      Fixtures.settle made

      expect(made.focused).to be picker.red
      expect(picker.value).to eq Color.rgb(200, 95, 135)
      expect(picker.swatch.color).to eq Color.rgb(200, 95, 135)
      expect(fields picker).to eq ["200", "95", "135", "#c85f87"]
      expect(changes root).to eq [Color.rgb(2, 95, 135), Color.rgb(20, 95, 135),
                                  Color.rgb(200, 95, 135)]
    end

    it "stays put while the text is not a number, and puts it back on Enter" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Tab Ctrl+U"
      Fixtures.type made, "2x6"
      Fixtures.settle made

      expect(picker.red.text).to eq "2x6"
      expect(picker.value).to eq Color.rgb(2, 0, 0)

      Fixtures.presses made, "Enter"
      expect(picker.red.text).to eq "0"
      expect(picker.value).to eq Color.rgb(0, 0, 0)
      expect(made.focused).to be picker.red
    end

    it "stays put on a number past 255, and clamps it on Enter" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Tab Ctrl+U"
      Fixtures.type made, "260"
      Fixtures.settle made

      expect(picker.value).to eq Color.rgb(26, 0, 0)

      Fixtures.presses made, "Enter"
      expect(picker.red.text).to eq "255"
      expect(picker.value).to eq Color.rgb(255, 0, 0)
    end

    it "steps from what is typed" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Tab Ctrl+U"
      Fixtures.type made, "40"
      Fixtures.presses made, "Up"

      expect(picker.value).to eq Color.rgb(41, 0, 0)
      expect(picker.red.text).to eq "41"
    end

    it "writes the field back from the value on Escape" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Tab Ctrl+U"
      Fixtures.type made, "200"
      Fixtures.presses made, "Escape"
      Fixtures.settle made

      expect(picker.value).to eq Color.rgb(200, 0, 0)
      expect(picker.red.text).to eq "200"
    end

    it "puts an empty channel back to its value on Enter" do
      picker = ColorPicker.new Color.rgb(40, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Tab Ctrl+U Enter"

      expect(picker.red.text).to eq "40"
      expect(picker.value).to eq Color.rgb(40, 0, 0)
    end

    it "steps with Left and Right, and goes to the ends with Home and End" do
      picker = ColorPicker.new Color.rgb(10, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Tab Right Right Left"
      expect(picker.value).to eq Color.rgb(11, 0, 0)

      Fixtures.presses made, "End"
      expect(picker.value).to eq Color.rgb(255, 0, 0)

      Fixtures.presses made, "Home"
      expect(picker.value).to eq Color.rgb(0, 0, 0)
      expect(picker.red.text).to eq "0"
    end

    it "sets all three channels from a hex edit" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      root = rooted picker
      made = app root
      Fixtures.presses made, "Tab Tab Tab Tab Ctrl+U"
      Fixtures.type made, "#3080c0"
      Fixtures.settle made

      expect(made.focused).to be picker.hex
      expect(picker.value).to eq Color.rgb(0x3080C0)
      expect(fields picker).to eq ["48", "128", "192", "#3080c0"]
      expect(changes root).to eq [Color.rgb(0x3080C0)]
    end

    it "takes hex without the #, and writes it back with one on leaving" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Tab Tab Tab Tab Ctrl+U"
      Fixtures.type made, "3080c0"
      Fixtures.presses made, "Tab"

      expect(picker.value).to eq Color.rgb(0x3080C0)
      expect(picker.hex.text).to eq "#3080c0"
    end

    it "steps a channel with Up and Down" do
      picker = ColorPicker.new Color.rgb(10, 20, 30)
      root = rooted picker
      made = app root
      Fixtures.presses made, "Tab Tab Up Up Down"

      expect(picker.value).to eq Color.rgb(10, 21, 30)
      expect(picker.green.text).to eq "21"
      expect(changes(root).size).to eq 3
    end

    it "moves the grid's cursor to a color the grid holds" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)
      Fixtures.presses made, "Tab Tab Tab Tab Ctrl+U"
      Fixtures.type made, "5f87af"

      expect(picker.grid.current.color).to eq Color.rgb(95, 135, 175)
    end
  end

  describe "at 256 colors" do
    it "snaps a field edit to the nearest index on leaving the field" do
      picker = ColorPicker.new Color.indexed(16), depth: Depth::Indexed256
      root = rooted picker
      made = app root
      Fixtures.presses made, "Tab Ctrl+U"
      Fixtures.type made, "100"
      Fixtures.settle made

      expect(picker.value).to eq Color.indexed(52)
      expect(fields picker).to eq ["100", "0", "0", "#5f0000"]

      Fixtures.presses made, "Tab"
      expect(fields picker).to eq ["95", "0", "0", "#5f0000"]
      expect(changes(root).last).to eq Color.indexed(52)
      expect(changes(root).all? &.indexed?).to be_true
    end

    it "snaps on Enter as well, and keeps the keyboard in the field" do
      picker = ColorPicker.new Color.indexed(16), depth: Depth::Indexed256
      made = app rooted(picker)
      Fixtures.presses made, "Tab Ctrl+U"
      Fixtures.type made, "100"
      Fixtures.presses made, "Enter"

      expect(made.focused).to be picker.red
      expect(picker.red.text).to eq "95"
    end

    it "steps to the next index along a channel" do
      picker = ColorPicker.new Color.indexed(16), depth: Depth::Indexed256
      made = app rooted(picker)
      Fixtures.presses made, "Tab Up"

      expect(picker.value).to eq Color.indexed(52)
      expect(picker.red.text).to eq "95"
    end

    it "holds a set value to the nearest index" do
      picker = ColorPicker.new Color.indexed(16), depth: Depth::Indexed256
      picker.value = Color.rgb 100, 0, 0

      expect(picker.value).to eq Color.indexed(52)
    end
  end

  describe "what it says" do
    it "emits Changed once per change, with the color" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      root = rooted picker
      made = app root
      Fixtures.presses made, "Enter"
      expect(changes root).to be_empty

      Fixtures.presses made, "Right Enter Right Enter"
      expect(changes root).to eq [Color.rgb(0, 0, 95), Color.rgb(0, 0, 135)]
    end

    it "emits nothing for #value=" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      root = rooted picker
      made = app root

      picker.value = Color.rgb 0x3080C0
      Fixtures.settle made
      expect(root.seen).to be_empty
      expect(fields picker).to eq ["48", "128", "192", "#3080c0"]
      expect(picker.swatch.color).to eq Color.rgb(0x3080C0)
    end

    it "keeps the fields' own messages to itself" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      root = rooted picker
      made = app root
      Fixtures.presses made, "Tab Escape"

      expect(root.of(TermBuf::Widgets::Field::Cancelled)).to be_empty
    end
  end

  describe "Tab" do
    it "moves between the grid and the fields, and wraps" do
      picker = ColorPicker.new Color.rgb(0, 0, 0)
      made = app rooted(picker)
      visited = [] of TermBuf::Widgets::Widget?

      5.times do
        Fixtures.presses made, "Tab"
        visited << made.focused
      end

      expect(visited).to eq [picker.red, picker.green, picker.blue, picker.hex, picker.grid]
    end
  end
end
