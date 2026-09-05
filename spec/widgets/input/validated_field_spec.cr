require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::ValidatedField do
  alias Field = TermBuf::Widgets::Field
  alias ValidatedField = TermBuf::Widgets::ValidatedField
  alias Validators = TermBuf::Widgets::Validators
  alias Log = Fixtures::MessageLog

  def panel(field : Field) : Log
    held = field.parent
    return held if held.is_a? Log

    root = Log.new
    root.add field
    root
  end

  def render(field : Field, columns : Int32 = 20, rows : Int32 = 4) : Array(String)
    Fixtures.render panel(field), columns, rows
  end

  def settle(field : Field, columns : Int32 = 20, rows : Int32 = 4) : Field
    Layout::Tree.new(panel(field), Rect.full(columns, rows)).layout
    field
  end

  def app(field : Field, columns : Int32 = 20, rows : Int32 = 4) : Fixtures::TestApp
    made = Fixtures::TestApp.new panel(field), columns, rows
    made.frame
    made
  end

  def required : ValidatedField
    made = ValidatedField.new
    made.validators << Validators.required
    made
  end

  describe "a line that passes" do
    it "leaves as an ordinary acceptance" do
      field = required
      field.text = "ok"
      root = panel field
      Fixtures.presses app(field), "Enter"

      expect(root.of(Field::Accepted).map &.text).to eq %w[ok]
      expect(root.of(ValidatedField::Invalid)).to be_empty
    end

    it "empties the field, the way a field with no rules does" do
      field = required
      field.text = "ok"
      Fixtures.presses app(field), "Enter"

      expect(field.text).to be_empty
      expect(field.error).to be_nil
    end
  end

  describe "a line that does not" do
    it "leaves as a refusal instead of an acceptance" do
      field = required
      root = panel field
      Fixtures.presses app(field), "Enter"
      refusals = root.of(ValidatedField::Invalid)

      expect(root.of(Field::Accepted)).to be_empty
      expect(refusals.size).to eq 1
      expect(refusals.first.errors).to eq ["required"]
      expect(refusals.first.message).to eq "required"
    end

    it "carries every message, in the order the rules were asked" do
      field = ValidatedField.new
      field.validators << Validators.required << Validators.numeric
      field.text = "abc"
      root = panel field
      Fixtures.presses app(field), "Enter"

      expect(root.of(ValidatedField::Invalid).first.errors).to eq ["a number"]
    end

    it "puts the line back, so there is something to correct" do
      field = required
      field.validators.clear
      field.validators << Validators.numeric
      field.text = "abc"
      Fixtures.presses app(field), "Enter"

      expect(field.text).to eq "abc"
      expect(field.buffer.cursor).to eq 3
    end

    it "draws the message under the line" do
      field = required
      field.validators.clear
      field.validators << Validators.numeric
      field.text = "abc"
      made = app field
      Fixtures.presses made, "Enter"

      expect(Fixtures.frame(made)[0, 2]).to eq ["abc", "a number"]
    end

    it "asks for a row to draw it in" do
      field = required
      field.validators.clear
      field.validators << Validators.numeric
      field.text = "abc"
      settle field

      expect(field.rect.height).to eq 1

      Fixtures.presses app(field), "Enter"
      settle field
      expect(field.rect.height).to eq 2
    end
  end

  describe "validating as the line is typed" do
    it "says nothing while it is off" do
      field = ValidatedField.new
      field.validators << Validators.numeric
      made = app field
      Fixtures.type made, "ab"

      expect(field.error).to be_nil
    end

    it "answers every keystroke while it is on" do
      field = ValidatedField.new validate_on_change: true
      field.validators << Validators.numeric
      made = app field
      Fixtures.type made, "ab"

      expect(field.error).to eq "a number"

      Fixtures.presses made, "Backspace Backspace"
      Fixtures.type made, "12"
      expect(field.error).to be_nil
    end

    it "answers a paste as well" do
      field = ValidatedField.new validate_on_change: true
      field.validators << Validators.numeric
      field.paste "abc"

      expect(field.error).to eq "a number"
    end
  end

  describe "the message" do
    it "goes away when the line is replaced from outside" do
      field = required
      Fixtures.presses app(field), "Enter"

      expect(field.invalid?).to be_true

      field.text = "ok"
      expect(field.error).to be_nil
    end

    it "goes away when the line is accepted and passes" do
      field = required
      made = app field
      Fixtures.presses made, "Enter"
      Fixtures.type made, "ok"
      Fixtures.presses made, "Enter"

      expect(field.error).to be_nil
    end
  end

  describe "a field with no rules" do
    it "behaves as a plain one" do
      field = ValidatedField.new
      field.text = "anything"
      root = panel field
      Fixtures.presses app(field), "Enter"

      expect(root.of(Field::Accepted).map &.text).to eq %w[anything]
      expect(field.validate).to be_empty
    end
  end
end
