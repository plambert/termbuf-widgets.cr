require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::NumberField do
  alias NumberField = TermBuf::Widgets::NumberField
  alias Log = Fixtures::MessageLog

  def rooted(field : NumberField) : Log
    root = Log.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    root.add field
    root
  end

  def app(root : Log, columns : Int32 = 24, rows : Int32 = 2) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  def changes(root : Log) : Array(Int32)
    root.of(NumberField::Changed).map &.value
  end

  describe "the value" do
    it "starts where it was told, held to the range" do
      expect(NumberField.new(value: 5, range: 0..10).value).to eq 5
      expect(NumberField.new(value: 50, range: 0..10).value).to eq 10
      expect(NumberField.new(value: -3, range: 0..10).value).to eq 0
    end

    it "draws the value" do
      field = NumberField.new value: 42, range: 0..100

      expect(Fixtures.render(rooted(field), 10, 1).first).to eq "42"
    end

    it "takes the end off an exclusive range" do
      expect(NumberField.new(value: 20, range: 0...10).range).to eq 0..9
    end

    it "refuses a range with nothing in it" do
      expect { NumberField.new(range: 5...5) }.to raise_error(ArgumentError)
    end

    it "is set by the application without a word" do
      field = NumberField.new value: 1, range: 0..10
      root = rooted field
      made = app root
      field.value = 7
      Fixtures.settle made

      expect(field.text).to eq "7"
      expect(root.of(NumberField::Changed)).to be_empty
    end

    it "holds a value set by the application to the range" do
      field = NumberField.new value: 1, range: 0..10
      field.value = 99

      expect(field.value).to eq 10
    end
  end

  describe "stepping" do
    it "steps up on Right and Up and down on Left and Down" do
      field = NumberField.new value: 5, range: 0..10
      root = rooted field
      made = app root

      Fixtures.presses made, "Right"
      Fixtures.presses made, "Up"
      Fixtures.presses made, "Left"
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Down"

      expect(changes root).to eq [6, 7, 6, 5, 4]
      expect(field.value).to eq 4
    end

    it "steps by its step" do
      field = NumberField.new value: 10, range: 0..100, step: 5
      root = rooted field
      made = app root
      Fixtures.presses made, "Right"

      expect(field.value).to eq 15
    end

    it "stops at the ends and says nothing there" do
      field = NumberField.new value: 9, range: 0..10
      root = rooted field
      made = app root
      Fixtures.presses made, "Right"
      Fixtures.presses made, "Right"
      Fixtures.presses made, "Right"

      expect(field.value).to eq 10
      expect(changes root).to eq [10]
    end

    it "goes to the ends of the range on Home and End" do
      field = NumberField.new value: 5, range: -3..12
      root = rooted field
      made = app root
      Fixtures.presses made, "End"
      expect(field.value).to eq 12

      Fixtures.presses made, "Home"
      expect(field.value).to eq(-3)
      expect(changes root).to eq [12, -3]
    end

    it "leaves Up and Down alone when it is told to" do
      field = NumberField.new value: 5, range: 0..10, up_down: false
      made = app rooted(field)
      Fixtures.presses made, "Up"

      expect(field.value).to eq 5
    end

    it "steps from what was typed when that is a number" do
      field = NumberField.new value: 5, range: 0..10
      made = app rooted(field)
      Fixtures.presses made, "Backspace"
      Fixtures.type made, "8"
      Fixtures.presses made, "Right"

      expect(field.value).to eq 9
    end

    it "does nothing while it is disabled" do
      field = NumberField.new value: 5, range: 0..10
      field.disabled = true
      field.step_by 1

      expect(field.value).to eq 5
      expect(field.focusable?).to be_false
    end
  end

  describe "typing" do
    it "takes typed digits on Enter and says so" do
      field = NumberField.new value: 5, range: 0..100
      root = rooted field
      made = app root
      Fixtures.presses made, "Backspace"
      Fixtures.type made, "42"
      Fixtures.presses made, "Enter"

      expect(field.value).to eq 42
      expect(field.text).to eq "42"
      expect(changes root).to eq [42]
    end

    it "holds a typed number to the range" do
      field = NumberField.new value: 5, range: 0..100
      made = app rooted(field)
      Fixtures.presses made, "Backspace"
      Fixtures.type made, "500"
      Fixtures.presses made, "Enter"

      expect(field.value).to eq 100
      expect(field.text).to eq "100"
    end

    it "puts the last value back when the text is not a number" do
      field = NumberField.new value: 5, range: 0..100
      root = rooted field
      made = app root
      Fixtures.type made, "x"
      Fixtures.presses made, "Enter"

      expect(field.value).to eq 5
      expect(field.text).to eq "5"
    end

    it "sends Accepted after the value" do
      field = NumberField.new value: 5, range: 0..100
      root = rooted field
      made = app root
      Fixtures.presses made, "Enter"

      expect(root.of(TermBuf::Widgets::Field::Accepted).map &.text).to eq ["5"]
    end
  end

  describe "size" do
    it "is as wide as the longest value and a cell for the cursor" do
      field = NumberField.new value: 5, range: -10..100
      Fixtures.render rooted(field), 24, 1

      expect(field.rect.width).to eq 4
    end

    it "makes room for the bar" do
      field = NumberField.new value: 5, range: 0..10, bar: true, bar_width: 6
      Fixtures.render rooted(field), 24, 1

      expect(field.rect.width).to eq 3 + 1 + 6
    end
  end

  describe "the bar" do
    it "fills by where the value sits in the range" do
      field = NumberField.new value: 5, range: 0..10, bar: true, bar_width: 10

      expect(Fixtures.render(rooted(field), 24, 1).first).to eq "5   █████░░░░░"
    end

    it "is drawn in ASCII where the block measures two cells" do
      wide = TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2
      field = NumberField.new value: 10, range: 0..10, bar: true, bar_width: 4

      expect(Fixtures.render(rooted(field), 24, 1, wide).first).to eq "10  ####"
    end
  end
end
