require "../../spec_helper"
require "../input/input_harness_spec"

Spectator.describe TermBuf::Widgets::NavigationBar do
  alias NavigationBar = TermBuf::Widgets::NavigationBar
  alias Log = Fixtures::MessageLog

  # A bar with a brand, two items and a trailing slot, which is every part of
  # one in the order they are drawn.
  def bar : NavigationBar
    made = NavigationBar.new brand: "tb", trailing: "12:04"
    made.add "files", hint: "F1"
    made.add "edit", hint: "F2"
    made
  end

  def rooted(bar : NavigationBar) : Log
    root = Log.new
    root.add bar
    root
  end

  def app(root : Log, columns : Int32 = 40, rows : Int32 = 3) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "the row" do
    it "writes the brand, the items and the trailing slot" do
      expect(Fixtures.render(rooted(bar), 40, 1).first)
        .to eq " tb  F1 files  F2 edit            12:04"
    end

    it "is one row tall, plus whatever padding it was given" do
      made = bar
      made.padding = TermBuf::Widgets::Layout::Padding.all 1

      root = rooted made
      Fixtures.render root, 40, 4

      expect(made.rect.height).to eq 3
    end

    it "grows to the width it is given" do
      made = bar
      root = rooted made
      Fixtures.render root, 40, 1

      expect(made.rect.width).to eq 40
    end
  end

  describe "running out of room" do
    it "gives up the trailing slot before it gives up a label" do
      # The brand and the labels come to 23 cells, the trailing slot to 7.
      expect(Fixtures.render(rooted(bar), 25, 1).first).to eq " tb  F1 files  F2 edit"
    end

    it "gives up the brand before it gives up a label" do
      expect(Fixtures.render(rooted(bar), 20, 1).first).to eq " F1 files  F2 edit"
    end

    it "collapses the items to their hints, brand and all, before that" do
      expect(Fixtures.render(rooted(bar), 18, 1).first).to eq " tb  F1  F2"
    end

    it "gives up the brand again rather than give up a hint" do
      expect(Fixtures.render(rooted(bar), 8, 1).first).to eq " F1  F2"
    end

    it "collapses to marks when even the hints will not fit" do
      expect(Fixtures.render(rooted(bar), 6, 1).first).to eq " …  …"
    end

    it "takes the ASCII mark where the pretty one is drawn wide" do
      cjk = TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2

      expect(Fixtures.render(rooted(bar), 6, 1, cjk).first).to eq " .  ."
    end

    it "says what it settled on" do
      made = bar
      policy = TermBuf::Unicode::WidthPolicy::DEFAULT

      expect(made.fit_for(40, policy).detail.full?).to be_true
      expect(made.fit_for(40, policy).trailing?).to be_true
      expect(made.fit_for(25, policy).trailing?).to be_false
      expect(made.fit_for(18, policy).detail.short?).to be_true
      expect(made.fit_for(18, policy).brand?).to be_true
      expect(made.fit_for(6, policy).brand?).to be_false
    end
  end

  describe "moving the highlight" do
    it "moves right and left, wrapping at either end" do
      made = bar
      running = app rooted(made)

      Fixtures.presses running, "Right"
      expect(made.selected).to eq 1

      Fixtures.presses running, "Right"
      expect(made.selected).to eq 0

      Fixtures.presses running, "Left"
      expect(made.selected).to eq 1
    end

    it "moves up and down when the bar runs that way" do
      made = NavigationBar.new direction: :column
      made.add "one"
      made.add "two"
      running = app rooted(made)

      Fixtures.presses running, "Down"
      expect(made.selected).to eq 1

      Fixtures.presses running, "Up"
      expect(made.selected).to eq 0
    end

    it "draws a column one item per row" do
      made = NavigationBar.new brand: "tb", direction: :column
      made.add "one"
      made.add "two"

      expect(Fixtures.render(rooted(made), 12, 4)).to eq [" tb", " one", " two", ""]
    end
  end

  describe "activating an item" do
    it "says which item it was" do
      made = bar
      root = rooted made
      running = app root

      Fixtures.presses running, "Right Enter"
      said = root.of(NavigationBar::Selected)

      expect(said.size).to eq 1
      expect(said.first.index).to eq 1
      expect(said.first.item).to be made.items[1]
    end

    it "sends the message the item carries as well" do
      carried = TermBuf::Widgets::NavigationBar::Selected.new bar, 7,
        NavigationBar::Item.new("elsewhere")
      made = NavigationBar.new
      made.add "go", message: carried
      root = rooted made
      running = app root

      Fixtures.presses running, "Enter"

      expect(root.of(NavigationBar::Selected).map &.index).to eq [0, 7]
    end

    it "runs the proc the item carries" do
      ran = 0
      made = NavigationBar.new
      made.add "go", action: -> { ran += 1; nil }
      running = app rooted(made)

      Fixtures.presses running, "Enter"

      expect(ran).to eq 1
    end

    it "activates the item that was clicked" do
      made = bar
      root = rooted made
      running = app root

      # The second item sits at columns 13 to 21, after the brand and the
      # first item.
      Fixtures.click running, 15, 0

      expect(made.selected).to eq 1
      expect(root.of(NavigationBar::Selected).map &.index).to eq [1]
    end

    it "does nothing for a click that lands on no item" do
      made = bar
      root = rooted made
      running = app root

      Fixtures.click running, 39, 0

      expect(root.of(NavigationBar::Selected)).to be_empty
    end
  end

  describe "the highlight" do
    it "is drawn reversed while the bar has the keyboard" do
      made = bar
      root = rooted made
      running = app root
      running.focus.focus made
      running.frame

      reversed = TermBuf::Attributes::Reverse

      expect(Fixtures.style_at(running.buffer, 5, 0).has? reversed).to be_true
      expect(Fixtures.style_at(running.buffer, 16, 0).has? reversed).to be_false
    end
  end
end
