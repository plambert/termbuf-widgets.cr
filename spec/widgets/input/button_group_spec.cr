require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::ButtonGroup do
  alias Button = TermBuf::Widgets::Button
  alias ButtonGroup = TermBuf::Widgets::ButtonGroup
  alias Log = Fixtures::MessageLog

  def rooted(group : ButtonGroup) : Log
    root = Log.new
    root.add group
    root
  end

  def app(root : Log, columns : Int32 = 30, rows : Int32 = 4) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "layout" do
    it "lays its buttons out in a row with a gap between them" do
      group = ButtonGroup.new %w[Yes No]

      expect(Fixtures.render(rooted(group), 30, 1).first).to eq " Yes   No"
    end

    it "lays them out in a column when it runs that way" do
      group = ButtonGroup.new %w[Yes No], direction: :column, gap: 0

      expect(Fixtures.render(rooted(group), 30, 2)).to eq [" Yes", " No"]
    end
  end

  describe "moving within the group" do
    it "moves right and left along a row" do
      group = ButtonGroup.new %w[Yes No Cancel]
      made = app rooted(group)

      Fixtures.presses made, "Right"
      expect(made.focused).to be group.buttons[1]

      Fixtures.presses made, "Left"
      expect(made.focused).to be group.buttons[0]
    end

    it "moves down and up a column" do
      group = ButtonGroup.new %w[Yes No], direction: :column
      made = app rooted(group)

      Fixtures.presses made, "Down"
      expect(made.focused).to be group.buttons[1]

      Fixtures.presses made, "Up"
      expect(made.focused).to be group.buttons[0]
    end

    it "wraps at either end" do
      group = ButtonGroup.new %w[Yes No Cancel]
      made = app rooted(group)

      Fixtures.presses made, "Left"
      expect(made.focused).to be group.buttons[2]

      Fixtures.presses made, "Right"
      expect(made.focused).to be group.buttons[0]
    end

    it "steps over a disabled button" do
      group = ButtonGroup.new %w[Yes No Cancel]
      group.buttons[1].disabled = true
      made = app rooted(group)

      Fixtures.presses made, "Right"

      expect(made.focused).to be group.buttons[2]
    end

    it "leaves the arrows across the group alone" do
      group = ButtonGroup.new %w[Yes No]
      made = app rooted(group)
      seen = [] of TermBuf::Event
      made.on_event = ->(event : TermBuf::Event) { seen << event; nil }

      Fixtures.presses made, "Down"

      expect(seen.size).to eq 1
      expect(made.focused).to be group.buttons[0]
    end
  end

  describe "an exclusive group" do
    it "chooses the button that was pressed" do
      group = ButtonGroup.new %w[Yes No], exclusive: true
      root = rooted group
      made = app root

      Fixtures.presses made, "Right"
      Fixtures.presses made, "Enter"

      expect(group.selected).to eq 1
      expect(group.selected_button).to be group.buttons[1]
    end

    it "says so, once, with the index" do
      group = ButtonGroup.new %w[Yes No], exclusive: true
      root = rooted group
      made = app root

      Fixtures.presses made, "Enter"
      changes = root.of(ButtonGroup::Changed)

      expect(changes.size).to eq 1
      expect(changes.first.index).to eq 0
      expect(changes.first.button).to be group.buttons[0]
    end

    it "unchooses whichever was chosen before" do
      group = ButtonGroup.new %w[Yes No], exclusive: true
      made = app rooted(group)

      Fixtures.presses made, "Enter"
      Fixtures.presses made, "Right"
      Fixtures.presses made, "Enter"

      expect(group.buttons.map &.selected?).to eq [false, true]
    end

    it "says nothing when the chosen button is pressed again" do
      group = ButtonGroup.new %w[Yes No], exclusive: true
      root = rooted group
      made = app root

      Fixtures.presses made, "Enter"
      root.forget
      Fixtures.presses made, "Enter"

      expect(root.of(ButtonGroup::Changed)).to be_empty
    end
  end

  describe "a group that is not exclusive" do
    it "keeps no choice at all" do
      group = ButtonGroup.new %w[Yes No]
      root = rooted group
      made = app root

      Fixtures.presses made, "Enter"

      expect(group.selected).to be_nil
      expect(root.of(ButtonGroup::Changed)).to be_empty
      expect(root.of(Button::Pressed).size).to eq 1
    end
  end

  describe "the choice set from outside" do
    it "marks the button without saying anything" do
      group = ButtonGroup.new %w[Yes No], exclusive: true
      root = rooted group
      made = app root
      group.selected = 1
      made.pump

      expect(group.buttons.map &.selected?).to eq [false, true]
      expect(root.of(ButtonGroup::Changed)).to be_empty
    end

    it "refuses an index nothing answers to" do
      group = ButtonGroup.new %w[Yes No], exclusive: true
      group.selected = 7

      expect(group.selected).to be_nil
    end
  end
end
