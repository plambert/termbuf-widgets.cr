require "../spec_helper"

Spectator.describe TermBuf::Widgets::Split do
  alias Split = TermBuf::Widgets::Split
  alias Panel = TermBuf::Widgets::Panel
  alias Label = TermBuf::Widgets::Label
  alias Button = TermBuf::Input::Mouse::Button
  alias Action = TermBuf::Input::Mouse::Action

  def pane(text : String) : Panel
    made = Panel.new width: Sizing.grow, height: Sizing.grow
    made.add Label.new(text)
    made
  end

  def split(**options) : Split
    Split.new pane("L"), pane("R"), **options
  end

  describe "how the room is shared" do
    it "gives each pane what its own sizing asks for" do
      made = split
      made.first.width = Sizing.fixed 3
      made.second.width = Sizing.grow

      Layout::Tree.new(made, Rect.full(10, 2)).layout
      expect(made.first.rect.width).to eq 3
      expect(made.divider.rect.x).to eq 3
      expect(made.second.rect.width).to eq 6
    end

    # A percent is a share of what the rule left, so two halves fill the box
    # between them rather than overflowing it by the rule's own cell.
    it "shares it by percent when that is what they ask for" do
      made = split
      made.first.width = Sizing.percent 50
      made.second.width = Sizing.percent 50

      Layout::Tree.new(made, Rect.full(21, 2)).layout
      expect(made.first.rect.width).to eq 10
      expect(made.divider.rect.width).to eq 1
      expect(made.second.rect.width).to eq 10
    end

    it "gives the odd cell to the first of two halves" do
      made = split
      made.first.width = Sizing.percent 50
      made.second.width = Sizing.percent 50

      Layout::Tree.new(made, Rect.full(20, 2)).layout
      expect(made.first.rect.width).to eq 10
      expect(made.second.rect.width).to eq 9
    end

    it "shares it evenly when both grow" do
      made = split
      Layout::Tree.new(made, Rect.full(11, 2)).layout

      expect(made.first.rect.width).to eq 5
      expect(made.second.rect.width).to eq 5
    end

    it "stacks the panes when it is a column" do
      made = split direction: Layout::Direction::Column
      Layout::Tree.new(made, Rect.full(6, 5)).layout

      expect(made.first.rect.height).to eq 2
      expect(made.divider.rect).to eq Rect.new(0, 2, 6, 1)
      expect(made.second.rect.height).to eq 2
    end

    it "draws the rule between them" do
      made = split at: 2
      expect(Fixtures.render(made, 6, 2)).to eq ["L │R", "  │"]
    end

    it "draws it across for a column" do
      made = split direction: Layout::Direction::Column, at: 1
      expect(Fixtures.render(made, 4, 3)).to eq ["L", "────", "R"]
    end
  end

  describe "#place" do
    it "puts the rule where it is told and keeps it there" do
      made = split
      tree = Layout::Tree.new made, Rect.full(12, 2)
      tree.layout

      made.place 4
      tree.layout_if_needed

      expect(made.at).to eq 4
      expect(made.first.rect.width).to eq 4
      expect(made.second.rect.width).to eq 7
    end

    it "gives what is left to the second pane when the split moves" do
      made = split at: 3
      tree = Layout::Tree.new made, Rect.full(12, 2)
      tree.layout
      expect(made.second.rect.width).to eq 8

      made.place 8
      tree.layout_if_needed
      expect(made.second.rect.width).to eq 3
    end

    it "keeps the first pane above the minimum" do
      made = split at: 5, minimum: 3
      tree = Layout::Tree.new made, Rect.full(12, 2)
      tree.layout

      made.place 0
      tree.layout_if_needed

      expect(made.at).to eq 3
    end

    it "keeps the second pane above it too" do
      made = split at: 5, minimum: 3
      tree = Layout::Tree.new made, Rect.full(12, 2)
      tree.layout

      made.place 40
      tree.layout_if_needed

      expect(made.at).to eq 8
      expect(made.second.rect.width).to eq 3
    end
  end

  describe "dragging the rule" do
    def wired(**options) : {Fixtures::TestApp, Split}
      made = Split.new pane("L"), pane("R"), **options
      app = Fixtures::TestApp.new made, 12, 2
      app.frame

      {app, made}
    end

    def mouse(app : Fixtures::TestApp, action : Action, x : Int32, y : Int32,
              button : Button = Button::Left) : Nil
      app.events.send TermBuf::Events::Mouse.new(button, x, y, TermBuf::Modifiers::None, action)
      app.pump
      app.frame
    end

    it "moves the split with the pointer" do
      app, made = wired at: 5
      mouse app, Action::Press, 5, 0
      mouse app, Action::Motion, 8, 0

      expect(made.at).to eq 8
      expect(made.first.rect.width).to eq 8
    end

    it "follows the pointer off the rule" do
      app, made = wired at: 5
      mouse app, Action::Press, 5, 0
      mouse app, Action::Motion, 1, 1

      expect(made.at).to eq 1
    end

    it "starts only on the rule itself" do
      app, made = wired at: 5
      mouse app, Action::Press, 1, 0
      mouse app, Action::Motion, 9, 0

      expect(made.at).to eq 5
      expect(made.dragging?).to be_false
    end

    it "lets go on the release" do
      app, made = wired at: 5
      mouse app, Action::Press, 5, 0
      mouse app, Action::Motion, 8, 0
      mouse app, Action::Release, 8, 0
      mouse app, Action::Motion, 2, 0

      expect(made.at).to eq 8
      expect(app.router.captured).to be_nil
    end

    it "respects the minimum while it drags" do
      app, made = wired at: 6, minimum: 4
      mouse app, Action::Press, 6, 0
      mouse app, Action::Motion, 0, 0

      expect(made.at).to eq 4
    end
  end
end
