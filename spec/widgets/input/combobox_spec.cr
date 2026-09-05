require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::Combobox do
  alias Combobox = TermBuf::Widgets::Combobox
  alias Option = TermBuf::Widgets::Option
  alias SelectionList = TermBuf::Widgets::SelectionList
  alias Log = Fixtures::MessageLog

  def options : Array(Option(String))
    Option.all %w[amber azure beige]
  end

  def rooted(box : Combobox(String), pad : Int32 = 0) : Log
    root = Log.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    root.padding = Layout::Padding.new pad, 0, 0, 0
    root.add box
    root
  end

  def app(root : Log, columns : Int32 = 20, rows : Int32 = 8) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "the drop-down" do
    it "starts shut" do
      box = Combobox.new options
      made = app rooted(box)

      expect(box.open?).to be_false
      expect(Fixtures.frame(made).first).to be_empty
    end

    it "opens as soon as something is typed" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.type made, "a"
      Fixtures.settle made

      expect(box.open?).to be_true
      expect(Fixtures.frame(made)[0, 3]).to eq ["a", "☐ amber", "☐ azure"]
    end

    it "narrows as more is typed" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.type made, "am"
      Fixtures.settle made

      expect(box.list.shown.map &.label).to eq ["amber"]
    end

    it "shuts when nothing matches, and opens again when something does" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.type made, "zz"
      Fixtures.settle made

      expect(box.open?).to be_false

      Fixtures.presses made, "Backspace"
      Fixtures.presses made, "Backspace"
      Fixtures.type made, "b"
      Fixtures.settle made

      expect(box.open?).to be_true
      expect(box.list.shown.map &.label).to eq ["beige"]
    end

    it "leaves the options themselves alone" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.type made, "am"
      Fixtures.settle made

      expect(box.options.map &.label).to eq %w[amber azure beige]
    end

    it "is opened by Down with nothing typed" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.presses made, "Down"

      expect(box.open?).to be_true
      expect(box.list.shown.size).to eq 3
    end
  end

  describe "moving through it" do
    it "moves the highlight without the keyboard leaving the field" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Down"

      expect(box.list.selected).to eq 1
      expect(made.focused).to be box.field
    end

    it "stops at the last option" do
      box = Combobox.new options
      made = app rooted(box)
      4.times { Fixtures.presses made, "Down" }

      expect(box.list.selected).to eq 2
    end

    it "moves back up" do
      box = Combobox.new options
      made = app rooted(box)
      3.times { Fixtures.presses made, "Down" }
      Fixtures.presses made, "Up"

      expect(box.list.selected).to eq 1
    end

    it "does nothing on Up while it is shut" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.presses made, "Up"

      expect(box.open?).to be_false
    end
  end

  describe "taking an option" do
    it "puts the highlighted label in the field and says which value it was" do
      box = Combobox.new options
      root = rooted box
      made = app root
      Fixtures.type made, "a"
      Fixtures.settle made
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Enter"
      chosen = root.of(Combobox::Chosen(String))

      expect(box.text).to eq "azure"
      expect(box.open?).to be_false
      expect(chosen.size).to eq 1
      expect(chosen.first.value).to eq "azure"
      expect(chosen.first.custom?).to be_false
    end

    it "takes the option that was clicked" do
      box = Combobox.new options
      root = rooted box
      made = app root
      Fixtures.presses made, "Down"
      made.frame
      Fixtures.click made, 3, 2

      expect(box.text).to eq "azure"
      expect(root.of(Combobox::Chosen(String)).map &.value).to eq ["azure"]
    end

    it "keeps the list's own messages to itself" do
      box = Combobox.new options
      root = rooted box
      made = app root
      Fixtures.presses made, "Down"
      made.frame
      Fixtures.click made, 3, 1

      expect(root.of(SelectionList::Changed(String))).to be_empty
    end

    it "shows everything again the next time it is opened" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.type made, "am"
      Fixtures.settle made
      Fixtures.presses made, "Enter"
      Fixtures.presses made, "Down"

      expect(box.text).to eq "amber"
      expect(box.list.shown.size).to eq 3
    end
  end

  describe "text of the user's own" do
    it "says nothing for text that is nobody's label when custom text is refused" do
      box = Combobox.new options
      root = rooted box
      made = app root
      Fixtures.type made, "zz"
      Fixtures.presses made, "Enter"

      expect(root.of(Combobox::Chosen(String))).to be_empty
      expect(box.text).to eq "zz"
    end

    it "hands it over with no value when custom text is allowed" do
      box = Combobox.new options, allow_custom: true
      root = rooted box
      made = app root
      Fixtures.type made, "zz"
      Fixtures.presses made, "Enter"
      chosen = root.of(Combobox::Chosen(String))

      expect(chosen.size).to eq 1
      expect(chosen.first.value).to be_nil
      expect(chosen.first.custom?).to be_true
      expect(chosen.first.text).to eq "zz"
    end

    it "still prefers the highlighted option when there is one" do
      box = Combobox.new options, allow_custom: true
      root = rooted box
      made = app root
      Fixtures.type made, "am"
      Fixtures.settle made
      Fixtures.presses made, "Enter"

      expect(root.of(Combobox::Chosen(String)).map &.value).to eq ["amber"]
    end
  end

  describe "Escape" do
    it "shuts the drop-down and leaves the text alone" do
      box = Combobox.new options
      root = rooted box
      made = app root
      Fixtures.type made, "a"
      Fixtures.settle made
      Fixtures.presses made, "Escape"

      expect(box.open?).to be_false
      expect(box.text).to eq "a"
      expect(root.of(TermBuf::Widgets::Field::Cancelled)).to be_empty
    end

    it "gives up on the line when the drop-down is already shut" do
      box = Combobox.new options
      root = rooted box
      made = app root
      Fixtures.type made, "a"
      Fixtures.settle made
      Fixtures.presses made, "Escape"
      Fixtures.presses made, "Escape"

      expect(root.of(TermBuf::Widgets::Field::Cancelled).size).to eq 1
    end
  end

  describe "where it opens" do
    it "hangs under the field" do
      box = Combobox.new options
      made = app rooted(box)
      Fixtures.presses made, "Down"
      made.frame

      expect(box.list.rect.y).to eq box.field.rect.y + box.field.rect.height
    end

    it "opens upward when there is no room below" do
      box = Combobox.new options
      made = app rooted(box, pad: 6), 20, 8
      Fixtures.presses made, "Down"
      made.frame

      expect(box.field.rect.y).to eq 6
      expect(box.list.rect.y).to eq 3
      expect(box.list.rect.y + box.list.rect.height).to eq box.field.rect.y
    end
  end
end
