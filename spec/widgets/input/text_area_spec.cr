require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::TextArea do
  alias TextArea = TermBuf::Widgets::TextArea
  alias Growth = TermBuf::Widgets::TextArea::Growth
  alias Wrap = TermBuf::Widgets::Layout::Wrap
  alias Log = Fixtures::MessageLog

  # A text area is put in a panel rather than made the root, because the root
  # is given the whole screen whatever its sizing says and half of these cases
  # are about what the area asks for.
  def panel(area : TextArea) : Log
    held = area.parent
    return held if held.is_a? Log

    root = Log.new
    root.add area
    root
  end

  def render(area : TextArea, columns : Int32 = 20, rows : Int32 = 6) : Array(String)
    Fixtures.render panel(area), columns, rows
  end

  # Lays it out without drawing, which is what the geometry cases want.
  def settle(area : TextArea, columns : Int32 = 20, rows : Int32 = 6) : TextArea
    Layout::Tree.new(panel(area), Rect.full(columns, rows)).layout
    area
  end

  def app(area : TextArea, columns : Int32 = 20, rows : Int32 = 6) : Fixtures::TestApp
    made = Fixtures::TestApp.new panel(area), columns, rows
    made.frame
    made
  end

  def type(area : TextArea, text : String) : Nil
    text.each_char { |char| area.press TermBuf::Key.character(char) }
  end

  def press(area : TextArea, keys : String) : Nil
    TermBuf::Key.parse(keys).each { |key| area.press key }
  end

  describe "typing" do
    it "puts a line break in on Enter" do
      area = TextArea.new
      type area, "ab"
      press area, "Enter"
      type area, "cd"

      expect(area.text).to eq "ab\ncd"
      expect(area.lines).to eq %w[ab cd]
    end

    it "draws a row per line" do
      area = TextArea.new "ab\ncd"

      expect(render(area, 20, 3)).to eq ["ab", "cd", ""]
    end

    it "keeps typing on the row the break made" do
      area = TextArea.new
      type area, "ab"
      press area, "Enter"
      type area, "cd"
      settle area, 20, 6

      expect(area.cursor_position).to eq({2, 1})
    end

    it "rubs the break out again" do
      area = TextArea.new "ab\ncd"
      area.buffer.move_to 3
      press area, "Backspace"

      expect(area.text).to eq "abcd"
    end

    it "takes a paste with breaks in it" do
      area = TextArea.new
      area.paste "one\ntwo"

      expect(area.lines).to eq %w[one two]
    end
  end

  describe "moving between rows" do
    it "goes down a row and up again" do
      area = TextArea.new "abcdef\nxy\nabcdef"
      settle area, 20, 6
      area.buffer.move_to 0
      press area, "Down"

      expect(area.buffer.cursor).to eq 7

      press area, "Up"
      expect(area.buffer.cursor).to eq 0
    end

    it "keeps the column it started from over a shorter row" do
      area = TextArea.new "abcdef\nxy\nabcdef"
      settle area, 20, 6
      area.buffer.move_to 6
      press area, "Down"

      # The short row has nowhere to put column six, so the cursor sits at the
      # end of it.
      expect(area.buffer.cursor).to eq 9

      press area, "Down"
      expect(area.buffer.cursor).to eq 16
    end

    it "forgets the column as soon as anything else happens" do
      area = TextArea.new "abcdef\nxy\nabcdef"
      settle area, 20, 6
      area.buffer.move_to 6
      press area, "Down"
      press area, "Left"
      press area, "Down"

      # The left key put the cursor a column in, and that is the column the
      # next down key aims at.
      expect(area.buffer.cursor).to eq 11
    end

    it "stays where it is at the top and the bottom" do
      area = TextArea.new "ab\ncd"
      settle area, 20, 6
      area.buffer.move_to 0
      press area, "Up"

      expect(area.buffer.cursor).to eq 0

      area.buffer.move_to 5
      press area, "Down"
      expect(area.buffer.cursor).to eq 5
    end

    it "moves by drawn row rather than by line" do
      area = TextArea.new "the quick brown fox"
      settle area, 10, 6
      area.buffer.move_to 0
      press area, "Down"

      expect(area.buffer.cursor).to eq 10
    end

    it "keeps the cursor at the end of a line rather than at the start of the next" do
      area = TextArea.new "ab\ncd"
      settle area, 20, 6
      area.buffer.move_to 2

      expect(area.cursor_position).to eq({2, 0})
    end
  end

  describe "wrapping" do
    it "breaks between words" do
      area = TextArea.new "the quick brown fox"

      expect(render(area, 10, 6)).to eq ["the quick", "brown fox", "", "", "", ""]
    end

    it "breaks anywhere when it is told to" do
      area = TextArea.new "abcdef", wrap: Wrap::Anywhere

      expect(render(area, 3, 6)).to eq ["abc", "def", "", "", "", ""]
    end

    it "breaks a word too long for a row of its own" do
      area = TextArea.new "an enormouslylongword"

      expect(render(area, 6, 6)).to eq ["an", "enormo", "uslylo", "ngword", "", ""]
    end

    it "does not break at all when it is told not to" do
      area = TextArea.new "the quick brown fox", wrap: Wrap::None
      settle area, 10, 6

      expect(area.rows.size).to eq 1
    end

    it "puts the cursor on the row the wrap moved it to" do
      area = TextArea.new "the quick brown fox"
      settle area, 10, 6

      expect(area.cursor_position).to eq({9, 1})
    end
  end

  describe "growth" do
    it "grows downward to the rows the text takes" do
      area = TextArea.new "one\ntwo\nthree"
      settle area, 20, 6

      expect(area.rect.height).to eq 3
    end

    it "grows no further than max_rows" do
      area = TextArea.new "one\ntwo\nthree", max_rows: 2
      settle area, 20, 6

      expect(area.rect.height).to eq 2
    end

    it "widens to the longest line when it grows sideways" do
      area = TextArea.new "ab\ncdef", growth: Growth::Horizontal, wrap: Wrap::None
      settle area, 20, 6

      # A cell past the longest line, so that typing at the end of it leaves
      # the cursor inside the box.
      expect(area.rect.width).to eq 5
    end

    it "takes the room it is given when it grows neither way" do
      area = TextArea.new "one", growth: Growth::Fixed
      settle area, 20, 4

      expect(area.rect.width).to eq 20
      expect(area.rect.height).to eq 4
    end

    it "grows both ways when it is told to" do
      area = TextArea.new "ab\ncdef", growth: Growth::Both, wrap: Wrap::None
      settle area, 20, 6

      expect(area.rect.width).to eq 5
      expect(area.rect.height).to eq 2
    end

    it "lays out again when the growth changes" do
      area = TextArea.new "one\ntwo\nthree"
      settle area, 20, 6
      area.growth = Growth::Fixed
      settle area, 20, 6

      expect(area.rect.height).to eq 6
    end
  end

  describe "scrolling" do
    it "scrolls down to keep the cursor in view" do
      area = TextArea.new "1\n2\n3\n4\n5", growth: Growth::Fixed

      expect(render(area, 20, 2)).to eq %w[4 5]
      expect(area.row_offset).to eq 3
    end

    it "scrolls back up when the cursor goes with it" do
      area = TextArea.new "1\n2\n3\n4\n5", growth: Growth::Fixed
      render area, 20, 2
      area.buffer.move_to 0

      expect(render(area, 20, 2)).to eq %w[1 2]
      expect(area.row_offset).to eq 0
    end

    it "scrolls sideways instead when nothing wraps" do
      area = TextArea.new "abcdefghij", growth: Growth::Fixed, wrap: Wrap::None

      expect(render(area, 5, 2)).to eq ["ghij", ""]
      expect(area.column_offset).to eq 6
    end
  end

  describe "what it says" do
    it "says the text changed" do
      area = TextArea.new
      root = panel area
      made = app area
      Fixtures.type made, "ab"
      Fixtures.settle made

      expect(root.of(TextArea::Changed).map &.text).to eq %w[a ab]
    end

    it "says nothing for a key that changed nothing" do
      area = TextArea.new "ab"
      root = panel area
      Fixtures.presses app(area), "Left"

      expect(root.of(TextArea::Changed)).to be_empty
    end

    it "says nothing when the text is set from outside" do
      area = TextArea.new
      root = panel area
      made = app area
      area.text = "ab"
      made.pump

      expect(root.of(TextArea::Changed)).to be_empty
    end

    it "hands nothing over on Enter" do
      area = TextArea.new "ab"
      root = panel area
      Fixtures.presses app(area), "Enter"

      expect(root.of(TextArea::Accepted)).to be_empty
      expect(area.text).to eq "ab\n"
    end

    it "hands the text over on Alt+Enter" do
      area = TextArea.new "ab"
      root = panel area
      Fixtures.presses app(area), "Alt+Enter"

      expect(root.of(TextArea::Accepted).map &.text).to eq %w[ab]
    end

    it "hands the text over on Ctrl+Enter" do
      area = TextArea.new "ab"
      root = panel area
      Fixtures.presses app(area), "Ctrl+Enter"

      expect(root.of(TextArea::Accepted).map &.text).to eq %w[ab]
    end

    it "leaves the text where it is when it hands it over" do
      area = TextArea.new "ab"
      Fixtures.presses app(area), "Alt+Enter"

      expect(area.text).to eq "ab"
    end

    it "takes the keys it is told to accept on instead" do
      area = TextArea.new "ab", accept_keys: TermBuf::Key.parse("Ctrl+S")
      root = panel area
      Fixtures.presses app(area), "Ctrl+S"

      expect(root.of(TextArea::Accepted).map &.text).to eq %w[ab]
    end
  end

  describe "the pointer" do
    it "puts the keyboard and the cursor where it was clicked" do
      area = TextArea.new "abcdef\nghij"
      made = app area
      Fixtures.click made, 2, 1

      expect(made.focused).to be area
      expect(area.buffer.cursor).to eq 9
    end
  end
end
