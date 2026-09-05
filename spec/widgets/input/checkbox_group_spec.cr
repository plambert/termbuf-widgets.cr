require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::CheckboxGroup do
  alias Checkbox = TermBuf::Widgets::Checkbox
  alias CheckboxGroup = TermBuf::Widgets::CheckboxGroup
  alias Log = Fixtures::MessageLog

  def rooted(group : CheckboxGroup) : Log
    root = Log.new
    root.add group
    root
  end

  def app(root : Log, columns : Int32 = 24, rows : Int32 = 6) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "building one" do
    it "takes plain labels" do
      group = CheckboxGroup.new %w[email sms]

      expect(group.labels).to eq %w[email sms]
      expect(group.values).to eq [false, false]
    end

    it "takes labels with the state they start in" do
      group = CheckboxGroup.new [{"email", true}, {"sms", false}]

      expect(group.values).to eq [true, false]
      expect(group.checked_labels).to eq ["email"]
    end

    it "draws one box a row" do
      group = CheckboxGroup.new [{"email", true}, {"sms", false}]

      expect(Fixtures.render(rooted(group), 20, 2)).to eq ["☑ email", "☐ sms"]
    end
  end

  describe "moving between the boxes" do
    it "moves down and up" do
      group = CheckboxGroup.new %w[email sms post]
      made = app rooted(group)

      Fixtures.presses made, "Down"
      expect(made.focused).to be group.boxes[1]

      Fixtures.presses made, "Up"
      expect(made.focused).to be group.boxes[0]
    end

    it "ticks the box the keyboard is on" do
      group = CheckboxGroup.new %w[email sms]
      made = app rooted(group)

      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"

      expect(group.values).to eq [false, true]
    end
  end

  describe "what the group says" do
    it "says which box changed and what it now says" do
      group = CheckboxGroup.new %w[email sms]
      root = rooted group
      Fixtures.presses app(root), "Space"
      changes = root.of(CheckboxGroup::Changed)

      expect(changes.size).to eq 1
      expect(changes.first.index).to eq 0
      expect(changes.first.checked?).to be_true
    end

    it "keeps the box's own message to itself" do
      group = CheckboxGroup.new %w[email]
      root = rooted group
      Fixtures.presses app(root), "Space"

      expect(root.of(Checkbox::Changed)).to be_empty
    end

    it "says nothing when the values are set from outside" do
      group = CheckboxGroup.new %w[email sms]
      root = rooted group
      made = app root
      group.values = [true, true]
      made.pump

      expect(group.values).to eq [true, true]
      expect(root.of(CheckboxGroup::Changed)).to be_empty
    end
  end

  describe "the bounds" do
    it "refuses a tick that would go past the maximum" do
      group = CheckboxGroup.new [{"email", true}], max: 1
      group.add "sms"
      root = rooted group
      made = app root

      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"
      refusals = root.of(CheckboxGroup::Refused)

      expect(group.values).to eq [true, false]
      expect(refusals.size).to eq 1
      expect(refusals.first.index).to eq 1
      expect(refusals.first.reason.max?).to be_true
      expect(root.of(CheckboxGroup::Changed)).to be_empty
    end

    it "refuses an untick that would go below the minimum" do
      group = CheckboxGroup.new [{"email", true}, {"sms", false}], min: 1
      root = rooted group
      made = app root

      Fixtures.presses made, "Space"
      refusals = root.of(CheckboxGroup::Refused)

      expect(group.values).to eq [true, false]
      expect(refusals.size).to eq 1
      expect(refusals.first.reason.min?).to be_true
    end

    it "allows a tick that stays inside the maximum" do
      group = CheckboxGroup.new %w[email sms post], max: 2
      root = rooted group
      made = app root

      Fixtures.presses made, "Space"
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"

      expect(group.values).to eq [true, true, false]
      expect(root.of(CheckboxGroup::Refused)).to be_empty
    end

    it "lets a full group be unticked and ticked elsewhere" do
      group = CheckboxGroup.new [{"email", true}, {"sms", false}], max: 1
      root = rooted group
      made = app root

      Fixtures.presses made, "Space"
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"

      expect(group.values).to eq [false, true]
      expect(root.of(CheckboxGroup::Refused)).to be_empty
    end

    it "counts no bound at all as no limit" do
      group = CheckboxGroup.new %w[email sms]
      root = rooted group
      made = app root

      Fixtures.presses made, "Space"
      Fixtures.presses made, "Down"
      Fixtures.presses made, "Space"

      expect(group.values).to eq [true, true]
      expect(root.of(CheckboxGroup::Refused)).to be_empty
    end
  end
end
