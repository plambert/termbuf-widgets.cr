require "../../spec_helper"
require "../input/input_harness_spec"

Spectator.describe TermBuf::Widgets::TabbedPanels do
  alias Button = TermBuf::Widgets::Button
  alias TabbedPanels = TermBuf::Widgets::TabbedPanels
  alias Log = Fixtures::MessageLog

  # Two tabs, the second of them closable, each holding something the keyboard
  # can land on.
  def panels : TabbedPanels
    made = TabbedPanels.new
    made.add "one", Button.new("alpha")
    made.add "two", Button.new("beta"), closable: true
    made
  end

  def rooted(panels : TabbedPanels) : Log
    root = Log.new
    root.add panels
    root
  end

  def app(root : Log, columns : Int32 = 30, rows : Int32 = 3) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "the strip" do
    it "writes a cell per tab, with a close glyph where there is one" do
      expect(Fixtures.render(rooted(panels), 30, 2).first).to eq " one  two ×"
    end

    it "takes the ASCII close glyph where the pretty one is drawn wide" do
      cjk = TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2

      expect(Fixtures.render(rooted(panels), 30, 2, cjk).first).to eq " one  two x"
    end

    it "runs down the side when the panels run across" do
      made = panels
      made.direction = :row

      expect(Fixtures.render(rooted(made), 30, 3)).to eq [" one    alpha", " two ×", ""]
    end
  end

  describe "the tab showing" do
    it "draws the active tab's widget and nothing else" do
      expect(Fixtures.render(rooted(panels), 30, 3)).to eq [" one  two ×", " alpha", ""]
    end

    it "lays out only the active tab's widget" do
      made = panels
      Fixtures.render rooted(made), 30, 3

      expect(made.tabs[0].widget.rect.width).to be > 0
      expect(made.tabs[1].widget.rect.width).to eq 0
    end

    it "keeps every tab's widget in the tree, hidden" do
      made = panels

      expect(made.body.children.size).to eq 2
      expect(made.body.children.map &.hidden?).to eq [false, true]
    end

    it "draws the other one once it is switched to" do
      made = panels
      made.activate 1

      expect(Fixtures.render(rooted(made), 30, 3)).to eq [" one  two ×", " beta", ""]
    end
  end

  describe "switching" do
    it "says which tab is showing now" do
      made = panels
      root = rooted made
      running = app root

      Fixtures.presses running, "Ctrl+PageDown"
      said = root.of(TabbedPanels::Changed)

      expect(made.active).to eq 1
      expect(said.size).to eq 1
      expect(said.first.index).to eq 1
      expect(said.first.tab).to be made.tabs[1]
    end

    it "wraps at either end" do
      made = panels
      running = app rooted(made)

      Fixtures.presses running, "Ctrl+PageUp"
      expect(made.active).to eq 1

      Fixtures.presses running, "Ctrl+PageDown"
      expect(made.active).to eq 0
    end

    it "takes the keyboard into the tab it switched to" do
      made = panels
      running = app rooted(made)

      Fixtures.presses running, "Ctrl+PageDown"

      expect(running.focused).to be made.tabs[1].widget
    end

    it "says nothing when the tab showing is activated again" do
      made = panels
      root = rooted made
      running = app root

      Fixtures.presses running, "Ctrl+PageDown"
      root.forget
      made.activate 1
      Fixtures.settle running

      expect(root.of(TabbedPanels::Changed)).to be_empty
    end

    it "takes other keys for it" do
      made = panels
      made.next_keys = ["Ctrl+n"]
      running = app rooted(made)

      Fixtures.presses running, "Ctrl+PageDown"
      expect(made.active).to eq 0

      Fixtures.presses running, "Ctrl+n"
      expect(made.active).to eq 1
    end
  end

  describe "the keyboard on the strip" do
    it "moves along it with the arrows" do
      made = panels
      running = app rooted(made)

      expect(running.focused).to be made.strip

      Fixtures.presses running, "Right"
      expect(made.active).to eq 1
    end

    it "steps down into the tab on Enter" do
      made = panels
      running = app rooted(made)

      Fixtures.presses running, "Enter"

      expect(running.focused).to be made.tabs[0].widget
    end
  end

  describe "the pointer" do
    it "shows the tab that was clicked" do
      made = panels
      running = app rooted(made)

      Fixtures.click running, 6, 0

      expect(made.active).to eq 1
    end

    it "closes the tab whose close glyph was clicked" do
      made = panels
      root = rooted made
      running = app root

      Fixtures.click running, 10, 0
      said = root.of(TabbedPanels::Closed)

      expect(made.tabs.map &.title).to eq ["one"]
      expect(said.size).to eq 1
      expect(said.first.index).to eq 1
    end
  end

  describe "taking a tab out" do
    it "takes its widget out of the tree with it" do
      made = panels
      gone = made.remove 0

      expect(gone.try &.title).to eq "one"
      expect(made.body.children.size).to eq 1
      expect(made.active).to eq 0
      expect(made.active_tab.try &.title).to eq "two"
    end

    it "answers nothing for an index there is no tab at" do
      expect(panels.remove(7)).to be_nil
    end
  end
end
