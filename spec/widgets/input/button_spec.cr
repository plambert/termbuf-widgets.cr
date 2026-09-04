require "../../spec_helper"
require "./input_harness_spec"

Spectator.describe TermBuf::Widgets::Button do
  alias Button = TermBuf::Widgets::Button
  alias Padding = TermBuf::Widgets::Layout::Padding
  alias Log = Fixtures::MessageLog
  alias Attributes = TermBuf::Attributes

  # A root holding *buttons*, which is also what hears what they say.
  def rooted(*buttons : Button) : Log
    root = Log.new direction: :row, gap: 1
    buttons.each { |button| root.add button }
    root
  end

  def app(root : Log, columns : Int32 = 24, rows : Int32 = 3) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "size" do
    it "fits its text and its padding" do
      button = Button.new "Save"
      Fixtures.render rooted(button), 24, 3

      expect(button.rect.width).to eq 6
      expect(button.rect.height).to eq 1
    end

    it "takes the padding it was given" do
      button = Button.new "Save", padding: Padding.new(0, 3, 0, 3)
      Fixtures.render rooted(button), 24, 3

      expect(button.rect.width).to eq 10
    end

    it "draws its text inside the padding" do
      button = Button.new "Save"

      expect(Fixtures.render(rooted(button), 24, 1).first).to eq " Save"
    end
  end

  describe "the keyboard" do
    it "takes focus" do
      button = Button.new "Save"
      made = app rooted(button)

      expect(made.focused).to be button
    end

    it "is pressed by Enter" do
      button = Button.new "Save"
      root = rooted button
      Fixtures.presses app(root), "Enter"

      expect(root.of(Button::Pressed).map &.button).to eq [button]
    end

    it "is pressed by Space" do
      button = Button.new "Save"
      root = rooted button
      Fixtures.presses app(root), "Space"

      expect(root.of(Button::Pressed).size).to eq 1
    end

    it "says which button was pressed" do
      first = Button.new "Yes"
      second = Button.new "No"
      root = rooted first, second
      made = app root

      Fixtures.presses made, "Tab"
      Fixtures.presses made, "Enter"

      expect(root.of(Button::Pressed).map &.button).to eq [second]
    end
  end

  describe "the pointer" do
    it "is pressed by a click inside it" do
      button = Button.new "Save"
      root = rooted button
      Fixtures.click app(root), 2, 0

      expect(root.of(Button::Pressed).size).to eq 1
    end

    it "is not pressed by a release that wandered off it" do
      button = Button.new "Save"
      root = rooted button
      made = app root

      Fixtures.mouse made, TermBuf::Input::Mouse::Action::Press, 2, 0
      Fixtures.mouse made, TermBuf::Input::Mouse::Action::Release, 20, 2

      expect(root.of(Button::Pressed)).to be_empty
    end

    it "takes the keyboard when it is clicked" do
      first = Button.new "Yes"
      second = Button.new "No"
      root = rooted first, second
      made = app root

      Fixtures.click made, second.rect.x + 1, 0

      expect(made.focused).to be second
    end
  end

  describe "styles" do
    it "draws the focused button in its focused style" do
      button = Button.new "Save"
      button.focused_style = TermBuf::Style::DEFAULT.bold
      made = app rooted(button)
      made.frame

      expect(Fixtures.style_at(made.buffer, 1, 0).has? Attributes::Bold).to be_true
    end

    it "draws a held button in its pressed style" do
      button = Button.new "Save"
      button.pressed_style = TermBuf::Style::DEFAULT.italic
      made = app rooted(button)

      Fixtures.mouse made, TermBuf::Input::Mouse::Action::Press, 2, 0
      made.frame

      expect(Fixtures.style_at(made.buffer, 1, 0).has? Attributes::Italic).to be_true
    end

    it "draws a disabled button in its disabled style" do
      button = Button.new "Save", disabled: true
      button.disabled_style = TermBuf::Style::DEFAULT.faint
      made = app rooted(button)
      made.frame

      expect(Fixtures.style_at(made.buffer, 1, 0).has? Attributes::Faint).to be_true
    end

    it "draws a selected button in its selected style" do
      button = Button.new "Save"
      button.selected = true
      button.selected_style = TermBuf::Style::DEFAULT.strike
      made = app rooted(button)
      # Focus is on the only button, and the focused style wins over the
      # selected one; a second button takes the keyboard away from it.
      made.root.add Button.new("Other")
      made.frame
      Fixtures.presses made, "Tab"
      made.frame

      expect(Fixtures.style_at(made.buffer, 1, 0).has? Attributes::Strike).to be_true
    end
  end

  describe "a disabled button" do
    it "is skipped by the tab order" do
      first = Button.new "Yes", disabled: true
      second = Button.new "No"
      made = app rooted(first, second)

      expect(made.focused).to be second
    end

    it "says nothing when it is clicked" do
      button = Button.new "Save", disabled: true
      root = rooted button
      Fixtures.click app(root), 2, 0

      expect(root.of(Button::Pressed)).to be_empty
    end

    it "swallows the click rather than letting it through" do
      button = Button.new "Save", disabled: true
      root = rooted button
      made = app root
      seen = 0
      root.keymap = nil

      made.on_event = ->(_event : TermBuf::Event) { seen += 1; nil }
      Fixtures.click made, 2, 0

      expect(seen).to eq 0
    end

    it "leaves the ring the moment it is disabled" do
      first = Button.new "Yes"
      second = Button.new "No"
      made = app rooted(first, second)
      first.disabled = true
      made.frame

      expect(made.focused).to be second
    end
  end
end
