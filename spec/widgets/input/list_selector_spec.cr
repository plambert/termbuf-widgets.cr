require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::ListSelector do
  alias ListSelector = TermBuf::Widgets::ListSelector
  alias Option = TermBuf::Widgets::Option
  alias SelectionList = TermBuf::Widgets::SelectionList
  alias Log = Fixtures::MessageLog

  def options : Array(Option(String))
    Option.all %w[read write execute]
  end

  def rooted(selector : ListSelector(String)) : Log
    root = Log.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    root.add selector
    root
  end

  def app(root : Log, columns : Int32 = 40, rows : Int32 = 5) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "what it draws" do
    it "puts the options on the left and nothing on the right" do
      selector = ListSelector.new options
      lines = Fixtures.render rooted(selector), 40, 4

      expect(lines[0]).to start_with "☐ read"
      expect(lines[0]).to contain "│ >"
      expect(selector.chosen_values).to be_empty
    end

    it "adds a second column of buttons when it is asked to order" do
      plain = ListSelector.new options
      ordered = ListSelector.new options, ordering: true

      expect(plain.order).to be_nil
      expect(plain.up_button).to be_nil
      expect(ordered.up_button.try &.text).to eq "^"
      expect(ordered.down_button.try &.text).to eq "v"
    end
  end

  describe "moving one across" do
    it "sends the row the keyboard is on across on Space" do
      selector = ListSelector.new options
      root = rooted selector
      made = app root
      Fixtures.presses made, "Space"

      expect(selector.chosen_values).to eq ["read"]
      expect(selector.available_values).to eq ["write", "execute"]
      expect(root.of(ListSelector::Changed(String)).map &.values).to eq [["read"]]
    end

    it "sends it across exactly once on Enter" do
      selector = ListSelector.new options
      root = rooted selector
      made = app root
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Enter"

      expect(selector.chosen_values).to eq ["write"]
      expect(selector.available_values).to eq ["read", "execute"]
      expect(root.of(ListSelector::Changed(String)).size).to eq 1
    end

    it "sends it back from the chosen list" do
      selector = ListSelector.new options
      root = rooted selector
      made = app root
      Fixtures.presses made, "Space"
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Space"

      expect(selector.chosen_values).to be_empty
      expect(selector.available_values).to eq ["write", "execute", "read"]
    end

    it "keeps the lists' own messages to itself" do
      selector = ListSelector.new options
      root = rooted selector
      made = app root
      Fixtures.presses made, "Enter"

      expect(root.of(SelectionList::Changed(String))).to be_empty
      expect(root.of(SelectionList::Confirmed(String))).to be_empty
    end

    it "sends across the option that was clicked" do
      selector = ListSelector.new options
      made = app rooted(selector)
      Fixtures.click made, 3, 1

      expect(selector.chosen_values).to eq ["write"]
    end
  end

  describe "the buttons" do
    it "sends one across when the add button is pressed" do
      selector = ListSelector.new options
      root = rooted selector
      made = app root
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Enter"

      expect(made.focused).to be selector.add_button
      expect(selector.chosen_values).to eq ["read"]
    end

    it "sends the lot across and back again" do
      selector = ListSelector.new options
      root = rooted selector
      made = app root
      selector.add_all
      Fixtures.settle made

      expect(selector.chosen_values).to eq ["read", "write", "execute"]
      expect(selector.available_values).to be_empty

      selector.remove_all
      Fixtures.settle made

      expect(selector.chosen_values).to be_empty
      expect(selector.available_values).to eq ["read", "write", "execute"]
      expect(root.of(ListSelector::Changed(String)).size).to eq 2
    end

    it "does nothing when there is nothing to move" do
      selector = ListSelector.new [] of Option(String)
      root = rooted selector
      made = app root
      selector.add_all
      Fixtures.settle made

      expect(root.of(ListSelector::Changed(String))).to be_empty
    end

    it "moves the arrows down the button column" do
      selector = ListSelector.new options
      made = app rooted(selector)
      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Down"

      expect(made.focused).to be selector.remove_button
    end
  end

  describe "ordering" do
    it "moves a chosen row up and says so" do
      selector = ListSelector.new options, ordering: true
      root = rooted selector
      made = app root
      selector.chosen_values = %w[read write execute]
      Fixtures.settle made
      selector.chosen.highlight 2
      root.forget
      selector.reorder(-1)
      Fixtures.settle made

      expect(selector.chosen_values).to eq ["read", "execute", "write"]
      expect(selector.chosen.selected).to eq 1
      expect(root.of(ListSelector::Changed(String)).map &.values).to eq [["read", "execute", "write"]]
    end

    it "moves it down" do
      selector = ListSelector.new options, ordering: true
      made = app rooted(selector)
      selector.chosen_values = %w[read write execute]
      Fixtures.settle made
      selector.chosen.highlight 0
      selector.reorder 1

      expect(selector.chosen_values).to eq ["write", "read", "execute"]
    end

    it "stays where it is at either end" do
      selector = ListSelector.new options, ordering: true
      made = app rooted(selector)
      selector.chosen_values = %w[read write]
      Fixtures.settle made
      selector.chosen.highlight 0
      selector.reorder(-1)

      expect(selector.chosen_values).to eq ["read", "write"]
    end
  end

  describe "setting it from outside" do
    it "takes the values out of whichever list holds them" do
      selector = ListSelector.new options
      root = rooted selector
      made = app root
      selector.chosen_values = %w[execute read]
      Fixtures.settle made

      expect(selector.chosen_values).to eq ["execute", "read"]
      expect(selector.available_values).to eq ["write"]
      expect(root.of(ListSelector::Changed(String))).to be_empty
    end
  end

  describe "tab" do
    it "moves between the three parts and back round" do
      selector = ListSelector.new options
      made = app rooted(selector)

      expect(made.focused).to be selector.available.list

      Fixtures.presses made, "Tab"
      expect(made.focused).to be selector.add_button

      Fixtures.presses made, "Tab"
      expect(made.focused).to be selector.chosen.list

      Fixtures.presses made, "Tab"
      expect(made.focused).to be selector.available.list
    end

    it "moves back the other way" do
      selector = ListSelector.new options
      made = app rooted(selector)
      Fixtures.presses made, "Shift+Tab"

      expect(made.focused).to be selector.chosen.list
    end

    it "counts the ordering column as a part of its own" do
      selector = ListSelector.new options, ordering: true
      made = app rooted(selector)
      3.times { Fixtures.presses made, "Tab" }

      expect(made.focused).to be selector.up_button
    end
  end
end
