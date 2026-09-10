require "../../spec_helper"
require "./overlay_harness_spec"

Spectator.describe TermBuf::Widgets::Drawer do
  alias Drawer = TermBuf::Widgets::Drawer
  alias Label = TermBuf::Widgets::Label

  # A screen with a drawer against *edge*, and something focusable in it.
  def staged(edge : Drawer::Edge = Drawer::Edge::Left,
             size : Int32 = 8,
             modal : Bool = false,
             backdrop : Bool = false,
             light_dismiss : Bool = false) : {Fixtures::Ground, Drawer, Fixtures::Box}
    ground = Fixtures::Ground.new
    drawer = Drawer.new edge, size: size, modal: modal, backdrop: backdrop,
      light_dismiss: light_dismiss
    inner = Fixtures::Box.new
    inner.focusable = true
    inner.width = Sizing.grow
    inner.height = Sizing.grow
    inner.mark = "D"
    drawer.add inner

    {ground, drawer, inner}
  end

  describe "where it sits" do
    it "fills the left edge" do
      ground, drawer, _inner = staged Drawer::Edge::Left
      drawer.open ground.app
      ground.app.frame

      expect(drawer.rect).to eq Rect.new(0, 0, 8, 12)
    end

    it "fills the right edge" do
      ground, drawer, _inner = staged Drawer::Edge::Right
      drawer.open ground.app
      ground.app.frame

      expect(drawer.rect).to eq Rect.new(32, 0, 8, 12)
    end

    it "fills the top edge" do
      ground, drawer, _inner = staged Drawer::Edge::Top, size: 3
      drawer.open ground.app
      ground.app.frame

      expect(drawer.rect).to eq Rect.new(0, 0, 40, 3)
    end

    it "fills the bottom edge" do
      ground, drawer, _inner = staged Drawer::Edge::Bottom, size: 3
      drawer.open ground.app
      ground.app.frame

      expect(drawer.rect).to eq Rect.new(0, 9, 40, 3)
    end

    it "moves to another edge when it is told to" do
      ground, drawer, _inner = staged Drawer::Edge::Left
      drawer.open ground.app
      drawer.edge = Drawer::Edge::Bottom
      drawer.size = 4
      ground.app.frame

      expect(drawer.rect).to eq Rect.new(0, 8, 40, 4)
    end

    it "draws itself over what is under it" do
      ground, drawer, _inner = staged

      expect(ground.lines.first).to eq "."

      drawer.open ground.app

      expect(ground.lines.first).to eq "D"
    end
  end

  describe "the keyboard" do
    it "leaves the rest of the screen reachable" do
      ground, drawer, inner = staged
      drawer.open ground.app

      expect(ground.app.focused).to be inner
      expect(ground.app.focus.scopes.size).to eq 1
      expect(ground.app.focus.focus(ground.under)).to be_true
    end

    it "holds the keyboard inside itself when it is modal" do
      ground, drawer, inner = staged modal: true
      drawer.open ground.app

      expect(ground.app.focused).to be inner
      expect(ground.app.focus.scopes.size).to eq 2
      expect(ground.app.focus.focus(ground.under)).to be_false
    end

    it "gives the keyboard back when it goes" do
      ground, drawer, _inner = staged modal: true
      drawer.open ground.app
      drawer.close

      expect(ground.app.focused).to be ground.under
      expect(ground.app.focus.scopes.size).to eq 1
    end
  end

  describe "closing" do
    it "goes on Escape, saying so" do
      ground, drawer, _inner = staged modal: true
      drawer.open ground.app
      ground.press "Escape"

      expect(drawer.open?).to be_false
      expect(ground.of(Drawer::Closed).map &.drawer).to eq [drawer]
    end

    it "goes on a click outside one that dismisses itself" do
      ground, drawer, _inner = staged light_dismiss: true
      drawer.open ground.app
      ground.press_at 30, 6

      expect(drawer.open?).to be_false
    end

    it "stays for a click outside one that does not" do
      ground, drawer, _inner = staged
      drawer.open ground.app
      ground.press_at 30, 6

      expect(drawer.open?).to be_true
    end

    it "leaves the screen as it was" do
      ground, drawer, _inner = staged
      drawer.open ground.app
      ground.app.frame
      drawer.close

      expect(ground.lines.first).to eq "."
    end
  end

  describe "the backdrop" do
    it "dims what is behind it when it was asked for" do
      ground, drawer, _inner = staged Drawer::Edge::Right, backdrop: true
      drawer.open ground.app

      expect(ground.style_at(0, 6).attributes.faint?).to be_true
    end

    it "leaves the characters behind it where they were" do
      ground, drawer, _inner = staged Drawer::Edge::Right, backdrop: true
      drawer.open ground.app

      expect(Fixtures.text_of(ground.painted).all? &.starts_with?(".")).to be_true
    end

    it "halves the colours of a cell that has any" do
      ground, drawer, _inner = staged Drawer::Edge::Right, backdrop: true
      ground.under.style = TermBuf::Style.new foreground: TermBuf::Color.rgb(200, 120, 60)
      drawer.open ground.app

      expect(ground.style_at(0, 6).foreground.channels).to eq({100, 60, 30})
    end

    it "leaves the screen alone when it was not asked for" do
      ground, drawer, _inner = staged Drawer::Edge::Right
      drawer.open ground.app

      expect(ground.style_at(0, 6).attributes.faint?).to be_false
    end
  end
end
