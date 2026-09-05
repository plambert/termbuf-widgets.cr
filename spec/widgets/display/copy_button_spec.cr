require "../../spec_helper"
require "../overlay/overlay_harness_spec"

Spectator.describe TermBuf::Widgets::CopyButton do
  alias CopyButton = TermBuf::Widgets::CopyButton
  alias Button = TermBuf::Widgets::Button

  # A screen, a log at the root, a copy button on it, a note of everything the
  # application was asked to copy, and a clock nothing waits on.
  class Staged
    getter root : Fixtures::MessageLog
    getter button : CopyButton
    getter app : Fixtures::TestApp
    getter clock : Fixtures::Ground::Clock
    getter copied = [] of String

    def initialize(@button : CopyButton, clipboard : Bool = true)
      @root = Fixtures::MessageLog.new width: Layout::Sizing.grow,
        height: Layout::Sizing.grow
      @root.add @button

      @app = Fixtures::TestApp.new @root, 30, 4
      @app.copy = ->(text : String) { @copied << text; nil } if clipboard
      @clock = Fixtures::Ground::Clock.new
      @clock.install @app
      @button.attach @app
      @app.frame
    end

    # Sends *keys* and lets everything they caused be delivered.
    def press(keys : String) : Nil
      @app.frame
      Fixtures.presses @app, keys
      @app.frame
    end

    # The messages of one kind that reached the root.
    def of(kind : Klass.class) : Array(Klass) forall Klass
      Fixtures.settle @app
      @root.of kind
    end

    # Fires the timer that is waiting.
    def fire : Nil
      @clock.fire @app, @clock.waiting.first
    end

    # What the screen shows.
    def lines : Array(String)
      @app.frame
      @app.lines
    end
  end

  def staged(button : CopyButton, **options) : Staged
    Staged.new button, **options
  end

  describe "copying" do
    it "asks the block what to copy at every press" do
      answer = "one"
      button = CopyButton.new "copy", -> { answer }
      stage = staged button

      button.press
      answer = "two"
      button.press

      expect(stage.copied).to eq %w[one two]
    end

    it "copies the same thing every time when it was given a string" do
      button = CopyButton.new "copy", "a token"
      stage = staged button
      button.press

      expect(stage.copied).to eq ["a token"]
    end

    it "says what it copied" do
      button = CopyButton.new "copy", "a token"
      stage = staged button
      button.press

      said = stage.of CopyButton::Copied
      expect(said.map &.text).to eq ["a token"]
      expect(said.first.button).to be button
    end

    it "copies on Enter while it has the keyboard" do
      button = CopyButton.new "copy", "a token"
      stage = staged button
      stage.press "Enter"

      expect(stage.copied).to eq ["a token"]
    end

    it "still says it was pressed" do
      button = CopyButton.new "copy", "a token"
      stage = staged button
      button.press

      expect(stage.of(Button::Pressed).size).to eq 1
    end
  end

  describe "the flash" do
    it "says so and arms a timer to put the label back" do
      button = CopyButton.new "copy", "a token", flash: 2.seconds
      stage = staged button
      button.press

      expect(button.text).to eq "copied"
      expect(button.flashing?).to be_true
      expect(stage.clock.armed.values).to eq [2.seconds]
    end

    it "puts the label back when the timer goes off" do
      button = CopyButton.new "copy", "a token"
      stage = staged button
      button.press
      stage.fire

      expect(button.text).to eq "copy"
      expect(button.flashing?).to be_false
      expect(stage.clock.waiting).to be_empty
    end

    it "starts the flash over rather than stuttering on a second press" do
      button = CopyButton.new "copy", "a token"
      stage = staged button
      button.press
      first = stage.clock.waiting.first
      button.press

      expect(stage.clock.cancelled).to eq [first]
      expect(stage.clock.waiting.size).to eq 1
      expect(button.text).to eq "copied"
    end

    it "shows on the screen" do
      button = CopyButton.new "copy", "a token"
      stage = staged button
      expect(stage.lines.first).to eq " copy"

      button.press
      expect(stage.lines.first).to eq " copied"
    end

    it "stays up where nothing wired a clock in" do
      button = CopyButton.new "copy", "a token"
      root = Fixtures::MessageLog.new
      root.add button
      app = Fixtures::TestApp.new root, 30, 4
      app.copy = ->(_text : String) { nil }
      button.attach app
      button.press

      expect(button.text).to eq "copied"
      expect(button.flashing?).to be_false
    end
  end

  describe "with no clipboard" do
    it "is disabled and says so" do
      button = CopyButton.new "copy", "a token"
      staged button, clipboard: false

      expect(button.disabled?).to be_true
      expect(button.text).to eq "no clipboard"
      expect(button.focusable?).to be_false
    end

    it "copies nothing when it is pressed anyway" do
      button = CopyButton.new "copy", "a token"
      stage = staged button, clipboard: false
      button.press

      expect(stage.copied).to be_empty
      expect(stage.of(CopyButton::Copied)).to be_empty
      expect(stage.of(Button::Pressed)).to be_empty
    end

    it "says whatever it was told to say instead" do
      button = CopyButton.new "copy", "a token", unavailable_text: "no way out"
      staged button, clipboard: false

      expect(button.text).to eq "no way out"
    end

    it "is disabled before anything attached it to an application" do
      button = CopyButton.new "copy", "a token"

      expect(button.disabled?).to be_true
      expect(button.text).to eq "no clipboard"
    end

    it "comes back to itself once an application with one is attached" do
      button = CopyButton.new "copy", "a token"
      staged button

      expect(button.disabled?).to be_false
      expect(button.text).to eq "copy"
    end
  end

  describe "#resting_text=" do
    it "takes effect at once when there is no flash up" do
      button = CopyButton.new "copy", "a token"
      staged button
      button.resting_text = "copy the token"

      expect(button.text).to eq "copy the token"
    end

    it "waits for the flash to come down" do
      button = CopyButton.new "copy", "a token"
      stage = staged button
      button.press
      button.resting_text = "copy the token"
      expect(button.text).to eq "copied"

      stage.fire
      expect(button.text).to eq "copy the token"
    end
  end
end
