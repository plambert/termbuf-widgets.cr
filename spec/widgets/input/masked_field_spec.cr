require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::MaskedField do
  alias Field = TermBuf::Widgets::Field
  alias MaskedField = TermBuf::Widgets::MaskedField
  alias ValidatedField = TermBuf::Widgets::ValidatedField
  alias Validators = TermBuf::Widgets::Validators
  alias Policy = TermBuf::Unicode::WidthPolicy
  alias Log = Fixtures::MessageLog

  def panel(field : Field) : Log
    held = field.parent
    return held if held.is_a? Log

    root = Log.new
    root.add field
    root
  end

  def render(field : Field, columns : Int32 = 20, rows : Int32 = 2) : Array(String)
    Fixtures.render panel(field), columns, rows
  end

  def app(field : Field, columns : Int32 = 20, rows : Int32 = 2) : Fixtures::TestApp
    made = Fixtures::TestApp.new panel(field), columns, rows
    made.frame
    made
  end

  def secret(text : String = "", **options) : MaskedField
    made = MaskedField.new(**options)
    made.text = text
    made
  end

  describe "drawing" do
    it "draws a mark for every character" do
      expect(render(secret("hello")).first).to eq "•••••"
    end

    it "draws the prompt as it stands" do
      field = secret "abc", prompt: Field::Prompt.new("word: ")

      expect(render(field).first).to eq "word: •••"
    end

    it "draws the mark it was given instead" do
      expect(render(secret("abc", mask: "#")).first).to eq "###"
    end

    it "shows the text when it is revealed" do
      field = secret "hello"
      field.reveal = true

      expect(render(field).first).to eq "hello"
    end

    it "shows the placeholder rather than a row of marks when it is empty" do
      field = secret placeholder: "none"

      expect(render(field).first).to eq "none"
    end
  end

  describe "choosing the mark" do
    it "takes the bullet when it measures a cell" do
      expect(MaskedField.mask_for(Policy::DEFAULT)).to eq MaskedField::MASK
    end

    it "falls back to ASCII when the mark measures wider than a cell" do
      expect(MaskedField.mask_for(Policy::DEFAULT, "✅")).to eq MaskedField::ASCII_MASK
    end
  end

  describe "the text" do
    it "keeps what was typed" do
      field = secret
      made = app field
      Fixtures.type made, "hunter2"

      expect(field.value).to eq "hunter2"
      expect(Fixtures.frame(made).first).to eq "•••••••"
    end

    it "is set through value as well" do
      field = secret
      field.value = "abc"

      expect(field.text).to eq "abc"
    end

    it "hands the real text over" do
      field = secret "abc"
      root = panel field
      Fixtures.presses app(field), "Enter"

      expect(root.of(Field::Accepted).map &.text).to eq %w[abc]
    end
  end

  describe "the cursor" do
    it "sits after the marks rather than after the characters" do
      field = secret "abc", prompt: Field::Prompt.new("> ")
      made = app field

      expect(made.frame).to eq({5, 0})
    end

    it "scrolls the marks along with it" do
      field = secret "abcdefgh"
      made = app field, 5, 2

      expect(Fixtures.frame(made).first).to eq "••••"
      expect(field.mask_offset).to eq 4
      expect(made.cursor).to eq({4, 0})
    end
  end

  describe "rules" do
    it "holds the line to them, since nobody can read it" do
      field = secret "abc"
      field.validators << Validators.length(min: 8)
      root = panel field
      made = app field
      Fixtures.presses made, "Enter"

      expect(root.of(ValidatedField::Invalid).map &.message).to eq ["at least 8 characters"]
      expect(field.value).to eq "abc"
      expect(Fixtures.frame(made)).to eq ["•••", "at least 8 character"]
    end
  end
end
