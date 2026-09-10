require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::SelectionList do
  alias Option = TermBuf::Widgets::Option
  alias SelectionList = TermBuf::Widgets::SelectionList
  alias Checkbox = TermBuf::Widgets::Checkbox
  alias Log = Fixtures::MessageLog

  def options : Array(Option(String))
    Option.all %w[alpha beta gamma]
  end

  def rooted(list : SelectionList(String)) : Log
    root = Log.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    root.add list
    root
  end

  def app(root : Log, columns : Int32 = 20, rows : Int32 = 4) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "what it draws" do
    it "shows one option a row, with the mark it stands at" do
      list = SelectionList.new options

      expect(Fixtures.render(rooted(list), 20, 3)).to eq ["☐ alpha", "☐ beta", "☐ gamma"]
    end

    it "marks the options that are chosen" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      list.select "beta"

      expect(Fixtures.render(rooted(list), 20, 3)).to eq ["☐ alpha", "☑ beta", "☐ gamma"]
    end

    it "draws the marks it was given instead" do
      list = SelectionList.new options, marks: Checkbox::ASCII

      expect(Fixtures.render(rooted(list), 20, 1).first).to eq "[ ] alpha"
    end

    it "takes the ASCII marks where the pretty ones are not a cell each" do
      list = SelectionList.new options
      wide = Checkbox::Marks.new "✅", "❎"
      list.marks = nil

      expect(list.marks_for(TermBuf::Unicode::WidthPolicy::DEFAULT)).to eq Checkbox::UNICODE
      expect(Checkbox.marks_for(TermBuf::Unicode::WidthPolicy::DEFAULT, wide)).to eq Checkbox::ASCII
    end

    it "cuts a label there is no room for" do
      list = SelectionList.new [Option.new("a very long label indeed", "x")]

      expect(Fixtures.render(rooted(list), 12, 1).first).to eq "☐ a very lo…"
    end

    it "draws each row through the block it was given" do
      list = SelectionList.new options
      list.on_draw = ->(view : TermBuf::View, _index : Int32, option : Option(String), _chosen : Bool, _focused : Bool) do
        view.write 0, 0, option.label.upcase
      end

      expect(Fixtures.render(rooted(list), 20, 2)).to eq ["ALPHA", "BETA"]
    end
  end

  describe "choosing" do
    it "chooses the row the keyboard is on with Space" do
      list = SelectionList.new options
      root = rooted list
      Fixtures.presses app(root), "Space"

      expect(list.values).to eq ["alpha"]
      expect(root.of(SelectionList::Changed(String)).map &.values).to eq [["alpha"]]
    end

    it "lets a chosen row go when Space comes again" do
      list = SelectionList.new options
      root = rooted list
      made = app root
      Fixtures.presses made, "Space"
      Fixtures.presses made, "Space"

      expect(list.values).to be_empty
    end

    it "keeps one at a time in single mode" do
      list = SelectionList.new options
      root = rooted list
      made = app root
      Fixtures.presses made, "Space"
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"

      expect(list.values).to eq ["beta"]
    end

    it "keeps as many as it is asked to in multi mode" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      root = rooted list
      made = app root
      Fixtures.presses made, "Space"
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"

      expect(list.values).to eq ["alpha", "beta"]
    end

    it "answers the values in the order the options were declared" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      list.select "gamma"
      list.select "alpha"

      expect(list.values).to eq ["alpha", "gamma"]
    end

    it "says nothing when the choice is set from outside" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      root = rooted list
      made = app root
      list.values = %w[alpha gamma]
      Fixtures.settle made

      expect(list.values).to eq ["alpha", "gamma"]
      expect(root.of(SelectionList::Changed(String))).to be_empty
    end

    it "lets a value go and clears the lot" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      list.values = %w[alpha beta]
      list.deselect "alpha"

      expect(list.values).to eq ["beta"]

      list.clear_selection
      expect(list.values).to be_empty
    end
  end

  describe "the cap" do
    it "refuses a choice that would go past it" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi, max_selections: 1
      root = rooted list
      made = app root
      Fixtures.presses made, "Space"
      root.forget
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"
      refusals = root.of(SelectionList::Refused(String))

      expect(list.values).to eq ["alpha"]
      expect(refusals.size).to eq 1
      expect(refusals.first.value).to eq "beta"
      expect(refusals.first.max).to eq 1
      expect(root.of(SelectionList::Changed(String))).to be_empty
    end

    it "lets a full list be unchosen and chosen elsewhere" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi, max_selections: 1
      root = rooted list
      made = app root
      Fixtures.presses made, "Space"
      Fixtures.presses made, "Space"
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"

      expect(list.values).to eq ["beta"]
      expect(root.of(SelectionList::Refused(String))).to be_empty
    end

    it "counts no cap at all as no limit" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      list.select "alpha"
      list.select "beta"
      list.select "gamma"

      expect(list.values).to eq ["alpha", "beta", "gamma"]
    end
  end

  describe "handing it over" do
    it "says what was chosen when Enter arrives" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      root = rooted list
      made = app root
      Fixtures.presses made, "Space"
      Fixtures.presses made, "Enter"

      expect(root.of(SelectionList::Confirmed(String)).map &.values).to eq [["alpha"]]
    end

    it "takes the row the keyboard is on when a single list has chosen nothing" do
      list = SelectionList.new options
      root = rooted list
      made = app root
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Enter"

      expect(root.of(SelectionList::Confirmed(String)).map &.values).to eq [["beta"]]
    end
  end

  describe "filtering" do
    it "narrows the rows to the labels the prefix starts" do
      list = SelectionList.new options, filterable: true
      root = rooted list
      made = app root
      Fixtures.type made, "g"
      Fixtures.settle made

      expect(list.filter).to eq "g"
      expect(list.shown.map &.label).to eq ["gamma"]
      expect(Fixtures.frame(made)).to eq ["/g", "☐ gamma", "", ""]
    end

    it "takes a character back off with Backspace" do
      list = SelectionList.new options, filterable: true
      made = app rooted(list)
      Fixtures.type made, "be"
      Fixtures.presses made, "Backspace"

      expect(list.filter).to eq "b"
      expect(list.shown.map &.label).to eq ["beta"]
    end

    it "leaves the options themselves alone" do
      list = SelectionList.new options, filterable: true
      made = app rooted(list)
      Fixtures.type made, "b"
      Fixtures.settle made

      expect(list.options.map &.label).to eq %w[alpha beta gamma]
      expect(list.size).to eq 3
    end

    it "keeps a choice the filter hid and gives it back" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi, filterable: true
      list.select "alpha"
      made = app rooted(list)
      Fixtures.type made, "g"
      Fixtures.settle made

      expect(list.values).to eq ["alpha"]

      list.filter = ""
      made.frame
      expect(list.values).to eq ["alpha"]
    end

    it "chooses the option behind the row rather than the row" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi, filterable: true
      made = app rooted(list)
      Fixtures.type made, "g"
      Fixtures.presses made, "Space"

      expect(list.values).to eq ["gamma"]
    end

    it "ignores what is typed at a list that does not filter" do
      list = SelectionList.new options
      made = app rooted(list)
      Fixtures.type made, "g"
      Fixtures.settle made

      expect(list.filter).to be_empty
      expect(list.shown.size).to eq 3
    end
  end

  describe "the pointer" do
    it "chooses the row that was clicked" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      root = rooted list
      made = app root
      Fixtures.click made, 3, 1

      expect(list.values).to eq ["beta"]
      expect(list.selected).to eq 1
    end

    it "does nothing for a click below the rows" do
      list = SelectionList.new options, mode: SelectionList::Mode::Multi
      made = app rooted(list), 20, 6
      Fixtures.click made, 3, 5

      expect(list.values).to be_empty
    end
  end
end
