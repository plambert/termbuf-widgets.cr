require "../../spec_helper"
require "./overlay_harness_spec"

Spectator.describe TermBuf::Widgets::Dialog do
  alias Dialog = TermBuf::Widgets::Dialog
  alias Label = TermBuf::Widgets::Label
  alias Attributes = TermBuf::Attributes

  # A screen with something under the dialog, and the dialog itself.
  def staged(backdrop : Bool = true, modal : Bool = true,
             actions : Enumerable(String) = {"Yes", "No"}) : {Fixtures::Ground, Dialog}
    ground = Fixtures::Ground.new
    dialog = Dialog.new "question", body: Label.new("go on?"), actions: actions,
      backdrop: backdrop, modal: modal
    {ground, dialog}
  end

  describe "opening" do
    it "puts itself in the tree it is opened on" do
      ground, dialog = staged
      dialog.open ground.app

      expect(dialog.parent).to be ground.root
      expect(dialog.open?).to be_true
    end

    it "puts the keyboard on the default action" do
      ground, dialog = staged
      dialog.open ground.app

      expect(ground.app.focused).to be dialog.buttons.first
    end

    it "puts it on another action when the default says so" do
      ground, dialog = staged
      dialog.default_action = 1
      dialog.open ground.app

      expect(ground.app.focused).to be dialog.buttons[1]
    end

    it "draws itself over what is under it" do
      ground, dialog = staged
      dialog.open ground.app

      expect(ground.lines.any?(&.includes?("question"))).to be_true
      expect(ground.lines.any?(&.includes?("Yes"))).to be_true
    end

    it "is nowhere on the screen before it is opened" do
      ground, dialog = staged
      ground.root.add dialog

      expect(ground.lines.any?(&.includes?("question"))).to be_false
    end
  end

  describe "the modal barrier" do
    it "refuses the keyboard to a widget under it" do
      ground, dialog = staged
      dialog.open ground.app

      expect(ground.app.focus.focus(ground.under)).to be_false
      expect(ground.app.focused).to be dialog.buttons.first
    end

    it "gives it back once the dialog has gone" do
      ground, dialog = staged
      dialog.open ground.app
      dialog.close

      expect(ground.app.focused).to be ground.under
      expect(ground.app.focus.focus(ground.under)).to be_true
    end

    it "keeps a key inside the dialog" do
      ground, dialog = staged
      dialog.open ground.app
      ground.under.seen.clear
      ground.press "Down"

      expect(ground.under.seen).to be_empty
    end

    it "keeps a click off what is behind it" do
      ground, dialog = staged
      dialog.open ground.app
      ground.under.seen.clear
      ground.click 0, 0

      expect(ground.under.seen).to be_empty
    end

    it "lets a click through once it has gone" do
      ground, dialog = staged
      dialog.open ground.app
      dialog.close
      ground.under.seen.clear
      ground.click 0, 0

      expect(ground.under.seen).not_to be_empty
    end
  end

  describe "answering it" do
    it "closes on Escape, saying nothing was chosen" do
      ground, dialog = staged
      dialog.open ground.app
      ground.press "Escape"

      expect(dialog.open?).to be_false
      expect(ground.of(Dialog::Closed).map &.result).to eq [nil]
    end

    it "closes on the default action, saying which it was" do
      ground, dialog = staged
      dialog.open ground.app
      ground.press "Enter"

      expect(dialog.open?).to be_false
      expect(ground.of(Dialog::Closed).map &.result).to eq [0]
    end

    it "closes on a button pressed with the keyboard" do
      ground, dialog = staged
      dialog.open ground.app
      ground.press "Right Space"

      expect(ground.of(Dialog::Closed).map &.result).to eq [1]
    end

    it "hides itself rather than leaving the tree" do
      ground, dialog = staged
      dialog.open ground.app
      ground.press "Escape"

      expect(dialog.parent).to be ground.root
      expect(dialog.hidden?).to be_true
      expect(ground.lines.any?(&.includes?("question"))).to be_false
    end

    it "opens again after it has been answered" do
      ground, dialog = staged
      dialog.open ground.app
      ground.press "Escape"
      dialog.open ground.app

      expect(dialog.open?).to be_true
      expect(ground.app.focused).to be dialog.buttons.first
    end
  end

  describe "the backdrop" do
    it "dims what is behind it" do
      ground, dialog = staged
      before = ground.style_at 0, 0
      dialog.open ground.app

      expect(before.attributes.faint?).to be_false
      expect(ground.style_at(0, 0).attributes.faint?).to be_true
    end

    it "leaves the screen alone when it was not asked for" do
      ground, dialog = staged backdrop: false
      dialog.open ground.app

      expect(ground.style_at(0, 0).attributes.faint?).to be_false
      expect(dialog.backdrop).to be_nil
    end

    it "stops dimming once the dialog has gone" do
      ground, dialog = staged
      dialog.open ground.app
      dialog.close

      expect(ground.style_at(0, 0).attributes.faint?).to be_false
    end
  end

  describe "the painting order" do
    it "puts the backdrop under the dialog and the dialog over everything" do
      ground, dialog = staged
      dialog.open ground.app
      ground.app.frame

      order = ground.app.tree.roots_in_z_order
      expect(order.size).to eq 4
      expect(order[0]).to be ground.root
      expect(order[1]).to be dialog.backdrop
      expect(order[2]).to be dialog.catcher
      expect(order[3]).to be dialog
    end
  end

  describe "the helpers" do
    it "asks a question with two answers" do
      ground = Fixtures::Ground.new
      dialog = Dialog.confirm ground.app, "go on?"

      expect(dialog.buttons.map &.text).to eq %w[Yes No]
      expect(dialog.open?).to be_true
    end

    it "says something with one way out" do
      ground = Fixtures::Ground.new
      dialog = Dialog.alert ground.app, "it did not work"

      expect(dialog.buttons.map &.text).to eq %w[OK]
      expect(dialog.open?).to be_true
    end
  end
end
