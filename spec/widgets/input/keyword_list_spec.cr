require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::KeywordList do
  alias KeywordList = TermBuf::Widgets::KeywordList
  alias Log = Fixtures::MessageLog

  def slugs : Array(String)
    %w[crystal crimson terminal widgets]
  end

  def rooted(list : KeywordList) : Log
    root = Log.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    root.add list
    root
  end

  def app(root : Log, columns : Int32 = 24, rows : Int32 = 6) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "what it draws" do
    it "draws a chip for every keyword, and the field under them" do
      list = KeywordList.new slugs, keywords: %w[crystal widgets]

      expect(Fixtures.render(rooted(list), 24, 3)[0, 2]).to eq ["[crystal] [widgets]", ""]
    end

    it "draws nothing at all while there are no keywords" do
      list = KeywordList.new slugs

      expect(list.chips.height_for_width(24, TermBuf::Unicode::WidthPolicy::DEFAULT)).to eq 0
    end

    it "wraps the chips and grows as it does" do
      list = KeywordList.new slugs, keywords: %w[crystal terminal widgets]
      made = app rooted(list), 20, 6

      expect(Fixtures.frame(made)[0, 2]).to eq ["[crystal] [terminal]", "[widgets]"]
      expect(list.chips.rect.height).to eq 2
    end

    it "puts the field below however many rows the chips came to" do
      list = KeywordList.new slugs, keywords: %w[crystal terminal widgets]
      made = app rooted(list), 20, 6
      made.frame

      expect(list.field.rect.y).to eq 2
    end
  end

  describe "adding one" do
    it "takes the text on Enter and says so" do
      list = KeywordList.new slugs
      root = rooted list
      made = app root
      Fixtures.type made, "widgets"
      Fixtures.presses made, "Enter"

      expect(list.keywords).to eq ["widgets"]
      expect(list.field.text).to be_empty
      expect(root.of(KeywordList::Added).map &.slug).to eq ["widgets"]
    end

    it "takes it on a comma too, and the comma never reaches the field" do
      list = KeywordList.new slugs
      made = app rooted(list)
      Fixtures.type made, "widgets"
      Fixtures.type made, ","
      Fixtures.settle made

      expect(list.keywords).to eq ["widgets"]
      expect(list.field.text).to be_empty
    end

    it "completes to the only slug the text begins" do
      list = KeywordList.new slugs
      made = app rooted(list)
      Fixtures.type made, "term"
      Fixtures.presses made, "Enter"

      expect(list.keywords).to eq ["terminal"]
    end

    it "keeps the text where it names more than one slug" do
      list = KeywordList.new slugs
      made = app rooted(list)
      Fixtures.type made, "cri"
      Fixtures.presses made, "Enter"

      expect(list.keywords).to eq ["crimson"]

      Fixtures.type made, "cr"
      Fixtures.presses made, "Enter"
      expect(list.keywords).to eq ["crimson", "cr"]
    end

    it "refuses one it already has" do
      list = KeywordList.new slugs, keywords: %w[widgets]
      root = rooted list
      made = app root
      Fixtures.type made, "widgets"
      Fixtures.presses made, "Enter"

      expect(list.keywords).to eq ["widgets"]
      expect(root.of(KeywordList::Added)).to be_empty
    end

    it "says nothing when the keywords are set from outside" do
      list = KeywordList.new slugs
      root = rooted list
      made = app root
      list.keywords = %w[crystal]
      Fixtures.settle made

      expect(list.keywords).to eq ["crystal"]
      expect(root.of(KeywordList::Added)).to be_empty
    end

    it "completes the word in the field with Tab" do
      list = KeywordList.new slugs
      made = app rooted(list)
      Fixtures.type made, "term"
      Fixtures.presses made, "Tab"

      expect(list.field.text).to eq "terminal"
      expect(list.keywords).to be_empty
    end
  end

  describe "taking one back" do
    it "selects the last chip on Backspace in an empty field" do
      list = KeywordList.new slugs, keywords: %w[crystal widgets]
      root = rooted list
      made = app root
      Fixtures.presses made, "Backspace"

      expect(list.selected).to eq 1
      expect(list.keywords).to eq ["crystal", "widgets"]
      expect(root.of(KeywordList::Removed)).to be_empty
    end

    it "removes it on the next Backspace and says so" do
      list = KeywordList.new slugs, keywords: %w[crystal widgets]
      root = rooted list
      made = app root
      Fixtures.presses made, "Backspace"
      Fixtures.presses made, "Backspace"

      expect(list.keywords).to eq ["crystal"]
      expect(root.of(KeywordList::Removed).map &.slug).to eq ["widgets"]
    end

    it "rubs a character out while there is text to rub out" do
      list = KeywordList.new slugs, keywords: %w[crystal]
      made = app rooted(list)
      Fixtures.type made, "abc"
      Fixtures.presses made, "Backspace"

      expect(list.field.text).to eq "ab"
      expect(list.selected).to be_nil
      expect(list.keywords).to eq ["crystal"]
    end

    it "removes the selected chip with Delete" do
      list = KeywordList.new slugs, keywords: %w[crystal widgets]
      root = rooted list
      made = app root
      Fixtures.presses made, "Backspace"
      Fixtures.presses made, "Delete"

      expect(list.keywords).to eq ["crystal"]
      expect(root.of(KeywordList::Removed).map &.slug).to eq ["widgets"]
    end
  end

  describe "moving between the chips" do
    it "steps back from the field onto the last chip" do
      list = KeywordList.new slugs, keywords: %w[crystal terminal widgets]
      made = app rooted(list)
      Fixtures.presses made, "Left"

      expect(list.selected).to eq 2
    end

    it "walks left along them" do
      list = KeywordList.new slugs, keywords: %w[crystal terminal widgets]
      made = app rooted(list)
      Fixtures.presses made, "Left"
      Fixtures.presses made, "Left"

      expect(list.selected).to eq 1
    end

    it "stops at the first one" do
      list = KeywordList.new slugs, keywords: %w[crystal terminal]
      made = app rooted(list)
      3.times { Fixtures.presses made, "Left" }

      expect(list.selected).to eq 0
    end

    it "lets the selection go on the way back into the field" do
      list = KeywordList.new slugs, keywords: %w[crystal terminal]
      made = app rooted(list)
      Fixtures.presses made, "Left"
      Fixtures.presses made, "Right"

      expect(list.selected).to be_nil
    end

    it "moves the cursor instead while there is text" do
      list = KeywordList.new slugs, keywords: %w[crystal]
      made = app rooted(list)
      Fixtures.type made, "ab"
      Fixtures.presses made, "Left"

      expect(list.selected).to be_nil
      expect(list.field.buffer.cursor).to eq 1
    end
  end

  describe "the pointer" do
    it "picks out the chip that was clicked" do
      list = KeywordList.new slugs, keywords: %w[crystal widgets]
      made = app rooted(list)
      made.frame
      Fixtures.click made, 12, 0

      expect(list.selected).to eq 1
    end

    it "leaves the selection alone for a click on nothing" do
      list = KeywordList.new slugs, keywords: %w[crystal]
      made = app rooted(list)
      made.frame
      Fixtures.click made, 18, 0

      expect(list.selected).to be_nil
    end
  end
end
