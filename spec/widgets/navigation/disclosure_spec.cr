require "../../spec_helper"
require "../input/input_harness_spec"

Spectator.describe TermBuf::Widgets::Disclosure do
  alias Disclosure = TermBuf::Widgets::Disclosure
  alias DisclosureGroup = TermBuf::Widgets::DisclosureGroup
  alias Label = TermBuf::Widgets::Label
  alias Log = Fixtures::MessageLog

  def section(title : String = "advanced") : Disclosure
    made = Disclosure.new title
    made.body.add Label.new("inside")
    made
  end

  def rooted(widget : TermBuf::Widgets::Widget) : Log
    root = Log.new
    root.add widget
    root
  end

  def app(root : Log, columns : Int32 = 20, rows : Int32 = 4) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "a section that is closed" do
    it "draws the header and nothing under it" do
      expect(Fixtures.render(rooted(section), 20, 3)).to eq ["▶ advanced", "", ""]
    end

    it "costs one row whatever is in it" do
      made = section
      Fixtures.render rooted(made), 20, 3

      expect(made.rect.height).to eq 1
    end

    it "keeps what is under it out of the layout" do
      made = section
      Fixtures.render rooted(made), 20, 3

      expect(made.body.hidden?).to be_true
      expect(made.body.rect.height).to eq 0
    end
  end

  describe "a section that is open" do
    it "draws what is under the header, indented" do
      made = section
      made.expanded = true

      expect(Fixtures.render(rooted(made), 20, 3)).to eq ["▼ advanced", "  inside", ""]
    end

    it "takes the ASCII expander where the pretty one is drawn wide" do
      cjk = TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2

      expect(Fixtures.render(rooted(section), 20, 2, cjk).first).to eq "+ advanced"
    end
  end

  describe "turning a section over" do
    it "opens it on Enter and says so" do
      made = section
      root = rooted made
      running = app root

      Fixtures.presses running, "Enter"
      said = root.of(Disclosure::Toggled)

      expect(made.expanded?).to be_true
      expect(said.size).to eq 1
      expect(said.first.expanded?).to be_true
      expect(said.first.disclosure).to be made
    end

    it "closes it again" do
      made = section
      root = rooted made
      running = app root

      Fixtures.presses running, "Enter"
      Fixtures.presses running, "Enter"

      expect(made.expanded?).to be_false
      expect(root.of(Disclosure::Toggled).map &.expanded?).to eq [true, false]
    end

    it "does it on Space too" do
      made = section
      running = app rooted(made)

      Fixtures.presses running, "Space"

      expect(made.expanded?).to be_true
    end

    it "does it on a click on the header" do
      made = section
      running = app rooted(made)

      Fixtures.click running, 3, 0

      expect(made.expanded?).to be_true
    end

    it "says nothing when the state is set from outside" do
      made = section
      root = rooted made
      running = app root
      made.expanded = true
      Fixtures.settle running

      expect(root.of(Disclosure::Toggled)).to be_empty
    end
  end

  describe "the header" do
    it "is where the keyboard lands" do
      made = section
      running = app rooted(made)

      expect(running.focused).to be made.header
    end

    it "says what the section says" do
      made = section
      made.title = "general"

      expect(Fixtures.render(rooted(made), 20, 2).first).to eq "▶ general"
    end
  end

  describe TermBuf::Widgets::DisclosureGroup do
    def group(exclusive : Bool) : DisclosureGroup
      made = DisclosureGroup.new exclusive: exclusive
      made.add "one"
      made.add "two"
      made
    end

    it "holds its sections in order" do
      expect(group(false).sections.map &.title).to eq ["one", "two"]
    end

    it "closes the section that was open when another opens" do
      made = group true
      running = app rooted(made)

      Fixtures.presses running, "Enter"
      expect(made.sections.map &.expanded?).to eq [true, false]

      Fixtures.presses running, "Tab Enter"
      expect(made.sections.map &.expanded?).to eq [false, true]
      expect(made.open_section).to be made.sections[1]
    end

    it "says one thing for the one section the user turned over" do
      made = group true
      root = rooted made
      running = app root

      Fixtures.presses running, "Enter"
      root.forget
      Fixtures.presses running, "Tab Enter"
      said = root.of(Disclosure::Toggled)

      expect(said.size).to eq 1
      expect(said.first.disclosure).to be made.sections[1]
    end

    it "leaves the others alone when it is not exclusive" do
      made = group false
      running = app rooted(made)

      Fixtures.presses running, "Enter"
      Fixtures.presses running, "Tab Enter"

      expect(made.sections.map &.expanded?).to eq [true, true]
    end
  end
end
