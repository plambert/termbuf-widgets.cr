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
end
