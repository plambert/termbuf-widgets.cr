require "../../spec_helper"
require "./overlay_harness_spec"

Spectator.describe TermBuf::Widgets::Popover do
  alias Popover = TermBuf::Widgets::Popover
  alias Label = TermBuf::Widgets::Label
  alias Point = Layout::AttachPoint
  alias Padding = Layout::Padding

  # A screen with a small target on it, and a popover hanging off the target.
  #
  # *align_y* is what puts the target at the top of the screen or at the
  # bottom of it, which is the difference between a popover that fits below it
  # and one that has to flip.
  def staged(element : Point = Point::LeftTop,
             parent : Point = Point::LeftBottom,
             align_y : Layout::Align = Layout::Align::Start,
             light_dismiss : Bool = true,
             modal : Bool = false,
             rows : Int32 = 12) : {Fixtures::TestApp, Fixtures::Box, Popover}
    root = Fixtures::MessageLog.new width: Sizing.grow, height: Sizing.grow,
      padding: Padding.new(1, 0, 1, 4), align_y: align_y

    target = Fixtures::Box.new
    target.width = Sizing.fixed 6
    target.height = Sizing.fixed 1
    target.focusable = true
    target.mark = "T"
    root.add target

    popover = Popover.new target, content: Label.new("menu"),
      element: element, parent: parent,
      light_dismiss: light_dismiss, modal: modal

    app = Fixtures::TestApp.new root, 30, rows
    app.frame
    {app, target, popover}
  end

  describe "where it lands" do
    it "hangs under the widget it is anchored to" do
      app, target, popover = staged
      popover.open app
      app.frame

      expect(target.rect).to eq Rect.new(4, 1, 6, 1)
      expect(popover.rect.x).to eq 4
      expect(popover.rect.y).to eq 2
      expect(popover.rect.height).to eq 3
    end

    it "flips above the target when there is no room below it" do
      app, target, popover = staged align_y: Layout::Align::End
      popover.open app
      app.frame

      expect(target.rect.y).to eq 10
      expect(popover.rect.y).to eq 7
      expect(popover.rect.bottom).to eq target.rect.y - 1
    end

    it "takes a different pair of attach points" do
      app, target, popover = staged
      popover.anchor_at Point::LeftTop, Point::RightTop
      popover.open app
      app.frame

      expect(popover.rect.x).to eq target.rect.right + 1
      expect(popover.rect.y).to eq target.rect.y
    end

    it "pins itself to the screen when it has no target" do
      app, _target, popover = staged
      popover.target = nil
      popover.open app
      app.frame

      expect(popover.rect.x).to eq 0
      expect(popover.rect.bottom).to eq 11
    end
  end

  describe "dismissal" do
    it "goes away on a click outside it" do
      app, _target, popover = staged
      popover.open app
      app.frame
      Fixtures.mouse app, TermBuf::Input::Mouse::Action::Press, 25, 9
      app.frame

      expect(popover.open?).to be_false
    end

    it "stays for a click inside it" do
      app, _target, popover = staged
      popover.open app
      app.frame
      spot = popover.rect
      Fixtures.mouse app, TermBuf::Input::Mouse::Action::Press, spot.x + 1, spot.y + 1
      app.frame

      expect(popover.open?).to be_true
    end

    it "stays when it was told not to dismiss itself" do
      app, _target, popover = staged light_dismiss: false
      popover.open app
      app.frame
      Fixtures.mouse app, TermBuf::Input::Mouse::Action::Press, 25, 9
      app.frame

      expect(popover.open?).to be_true
      expect(popover.catcher).to be_nil
    end

    it "goes away on Escape while the keyboard is inside it" do
      app, _target, popover = staged
      inner = Fixtures::Box.new
      inner.focusable = true
      popover.add inner
      popover.open app

      expect(app.focused).to be inner
      Fixtures.presses app, "Escape"

      expect(popover.open?).to be_false
    end
  end

  describe "what it does to the rest of the screen" do
    it "leaves the keyboard where it can reach everything" do
      app, target, popover = staged
      app.focus.focus target
      popover.open app

      expect(app.focus.scopes.size).to eq 1
      expect(app.focus.focus(target)).to be_true
    end

    it "holds the keyboard inside itself when it is modal" do
      app, target, popover = staged modal: true
      inner = Fixtures::Box.new
      inner.focusable = true
      popover.add inner
      popover.open app

      expect(app.focus.scopes.size).to eq 2
      expect(app.focus.focus(target)).to be_false
    end
  end
end
