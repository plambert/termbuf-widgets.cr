require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::Checkbox do
  alias Checkbox = TermBuf::Widgets::Checkbox
  alias Marks = TermBuf::Widgets::Checkbox::Marks
  alias Glyphs = TermBuf::Widgets::Glyphs
  alias Log = Fixtures::MessageLog
  alias Policy = TermBuf::Unicode::WidthPolicy

  def rooted(*boxes : Checkbox) : Log
    root = Log.new
    boxes.each { |box| root.add box }
    root
  end

  def app(root : Log, columns : Int32 = 24, rows : Int32 = 3) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "drawing" do
    it "draws the mark and then the label" do
      box = Checkbox.new "Wrap"

      expect(Fixtures.render(rooted(box), 20, 1).first).to eq "☐ Wrap"
    end

    it "draws the ticked mark when it is ticked" do
      box = Checkbox.new "Wrap", checked: true

      expect(Fixtures.render(rooted(box), 20, 1).first).to eq "☑ Wrap"
    end

    it "draws the marks it was given instead" do
      box = Checkbox.new "Wrap", marks: Checkbox::ASCII

      expect(Fixtures.render(rooted(box), 20, 1).first).to eq "[ ] Wrap"
    end

    it "cuts a label there is no room for" do
      box = Checkbox.new "Wrap long lines"

      expect(Fixtures.render(rooted(box), 8, 1).first).to eq "☐ Wrap l"
    end
  end

  describe "size" do
    it "fits the mark, a gap, and the label" do
      box = Checkbox.new "Wrap"
      Fixtures.render rooted(box), 24, 1

      expect(box.rect.width).to eq 6
    end

    it "is as wide as its widest mark whichever way it stands" do
      unticked = Checkbox.new "Wrap", marks: Checkbox::ASCII
      ticked = Checkbox.new "Wrap", checked: true, marks: Checkbox::ASCII
      Fixtures.render rooted(unticked, ticked), 24, 2

      expect(unticked.rect.width).to eq ticked.rect.width
      expect(ticked.rect.width).to eq 8
    end
  end

  describe "choosing the marks" do
    it "takes the pretty pair when every mark is one cell" do
      expect(Checkbox.marks_for(Policy::DEFAULT)).to eq Checkbox::UNICODE
    end

    it "falls back to ASCII when a mark measures wider than a cell" do
      wide = Marks.new "✅", "❎"

      expect(Checkbox.marks_for(Policy::DEFAULT, wide)).to eq Checkbox::ASCII
    end

    it "measures under the policy it is given" do
      expect(Glyphs.single_cell?(["✅"], Policy::DEFAULT)).to be_false
      expect(Glyphs.single_cell?(Checkbox::UNICODE.both, Policy::DEFAULT)).to be_true
    end
  end

  describe "toggling" do
    it "is turned over by Space" do
      box = Checkbox.new "Wrap"
      root = rooted box
      Fixtures.presses app(root), "Space"

      expect(box.checked?).to be_true
      expect(root.of(Checkbox::Changed).map &.checked?).to eq [true]
    end

    it "is turned back by Space again" do
      box = Checkbox.new "Wrap", checked: true
      root = rooted box
      Fixtures.presses app(root), "Space"

      expect(box.checked?).to be_false
      expect(root.of(Checkbox::Changed).map &.checked?).to eq [false]
    end

    it "is turned over by a click" do
      box = Checkbox.new "Wrap"
      root = rooted box
      Fixtures.click app(root), 0, 0

      expect(box.checked?).to be_true
      expect(root.of(Checkbox::Changed).size).to eq 1
    end

    it "says nothing when the state is set from outside" do
      box = Checkbox.new "Wrap"
      root = rooted box
      made = app root
      box.checked = true
      made.pump

      expect(box.checked?).to be_true
      expect(root.of(Checkbox::Changed)).to be_empty
    end
  end

  describe "a disabled box" do
    it "is skipped by the tab order" do
      first = Checkbox.new "One", disabled: true
      second = Checkbox.new "Two"
      made = app rooted(first, second)

      expect(made.focused).to be second
    end

    it "does not turn over when it is clicked" do
      box = Checkbox.new "Wrap", disabled: true
      root = rooted box
      Fixtures.click app(root), 0, 0

      expect(box.checked?).to be_false
      expect(root.of(Checkbox::Changed)).to be_empty
    end
  end
end
