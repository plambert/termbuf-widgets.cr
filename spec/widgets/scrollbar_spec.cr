require "../spec_helper"

Spectator.describe TermBuf::Widgets::Scrollbar do
  alias Scrollbar = TermBuf::Widgets::Scrollbar
  alias Scrollable = TermBuf::Widgets::Scrollable
  alias Panel = TermBuf::Widgets::Panel
  alias Label = TermBuf::Widgets::Label
  alias Button = TermBuf::Input::Mouse::Button
  alias Action = TermBuf::Input::Mouse::Action

  # A scrollable of *count* one-row labels with a bar beside it, laid out at
  # *columns* by *rows*.
  def wired(count : Int32, columns : Int32 = 6, rows : Int32 = 4) : {Scrollable, Scrollbar, Panel}
    root = Panel.new direction: Layout::Direction::Row,
      width: Sizing.grow, height: Sizing.grow
    panel = Scrollable.new
    count.times { |index| panel.add Label.new("r#{index}") }
    bar = Scrollbar.new panel
    root.add panel, bar

    Layout::Tree.new(root, Rect.full(columns, rows)).layout
    {panel, bar, root}
  end

  describe "its size" do
    it "is one cell wide and as long as there is room" do
      _, bar, _ = wired 8

      expect(bar.rect).to eq Rect.new(5, 0, 1, 4)
    end

    it "runs across for a panel that scrolls sideways" do
      panel = Scrollable.new direction: Layout::Direction::Row
      bar = Scrollbar.new panel

      expect(bar.vertical?).to be_false
      expect(bar.height).to eq Sizing.fixed(1)
    end

    it "takes the way it was told to run over what the panel clips" do
      panel = Scrollable.new direction: Layout::Direction::Row
      bar = Scrollbar.new panel, orientation: Scrollbar::Orientation::Vertical

      expect(bar.vertical?).to be_true
    end
  end

  describe "the thumb" do
    it "is the share of the content that is showing" do
      _, bar, _ = wired 8

      expect(bar.length).to eq 4
      expect(bar.thumb_size).to eq 2
      expect(bar.thumb_start).to eq 0
    end

    it "fills the bar when everything fits" do
      _, bar, _ = wired 2

      expect(bar.thumb_size).to eq 4
      expect(bar.thumb_start).to eq 0
    end

    it "is never shorter than a cell" do
      _, bar, _ = wired 400

      expect(bar.thumb_size).to eq 1
    end

    it "reaches the far end when the content does" do
      panel, bar, _ = wired 8
      panel.scroll_by dy: 40

      expect(bar.thumb_start + bar.thumb_size).to eq bar.length
    end

    it "moves in proportion to the scroll" do
      panel, bar, _ = wired 12

      expect(bar.thumb_start).to eq 0

      # Four of eight scrollable rows is half the travel of three cells, and a
      # half rounds up.
      panel.scroll_by dy: 4
      expect(bar.thumb_start).to eq 2

      panel.scroll_by dy: 4
      expect(bar.thumb_start).to eq 3
    end

    it "is drawn on the track" do
      panel, _, root = wired 8
      panel.scroll_by dy: 4

      expect(Fixtures.render(root, 6, 4)).to eq ["r4   │", "r5   │", "r6   █", "r7   █"]
    end
  end

  describe "a press" do
    def app_for(count : Int32, columns : Int32 = 6,
                rows : Int32 = 4) : {Fixtures::TestApp, Scrollable, Scrollbar}
      root = Panel.new direction: Layout::Direction::Row,
        width: Sizing.grow, height: Sizing.grow
      panel = Scrollable.new
      count.times { |index| panel.add Label.new("r#{index}") }
      bar = Scrollbar.new panel
      root.add panel, bar

      app = Fixtures::TestApp.new root, columns, rows
      app.frame
      {app, panel, bar}
    end

    def mouse(app : Fixtures::TestApp, action : Action, x : Int32, y : Int32,
              button : Button = Button::Left) : Nil
      app.events.send TermBuf::Events::Mouse.new(button, x, y, TermBuf::Modifiers::None, action)
      app.pump
    end

    it "pages towards the track it was pressed on" do
      app, panel, _ = app_for 12
      mouse app, Action::Press, 5, 3

      expect(panel.scroll_y).to eq 4
    end

    it "pages back" do
      app, panel, _ = app_for 12
      panel.scroll_by dy: 6
      app.frame
      mouse app, Action::Press, 5, 0

      expect(panel.scroll_y).to eq 2
    end

    it "hands a wheel notch to the panel" do
      app, panel, _ = app_for 12
      mouse app, Action::Press, 5, 1, Button::WheelDown

      expect(panel.scroll_y).to eq 3
    end
  end

  describe "a drag" do
    def app_for(count : Int32) : {Fixtures::TestApp, Scrollable}
      root = Panel.new direction: Layout::Direction::Row,
        width: Sizing.grow, height: Sizing.grow
      panel = Scrollable.new
      count.times { |index| panel.add Label.new("r#{index}") }
      root.add panel, Scrollbar.new(panel)

      app = Fixtures::TestApp.new root, 6, 4
      app.frame
      {app, panel}
    end

    def mouse(app : Fixtures::TestApp, action : Action, x : Int32, y : Int32) : Nil
      app.events.send TermBuf::Events::Mouse.new(Button::Left, x, y,
        TermBuf::Modifiers::None, action)
      app.pump
    end

    it "moves the panel with the thumb" do
      app, panel = app_for 12
      mouse app, Action::Press, 5, 0
      mouse app, Action::Motion, 5, 3

      expect(panel.scroll_y).to eq 8
    end

    it "follows the pointer off the bar" do
      app, panel = app_for 12
      mouse app, Action::Press, 5, 0
      mouse app, Action::Motion, 0, 2

      expect(panel.scroll_y).to be > 0
    end

    it "lets go on the release" do
      app, panel = app_for 12
      mouse app, Action::Press, 5, 0
      mouse app, Action::Motion, 5, 3
      mouse app, Action::Release, 5, 3
      moved = panel.scroll_y
      mouse app, Action::Motion, 5, 0

      expect(panel.scroll_y).to eq moved
      expect(app.router.captured).to be_nil
    end

    it "does nothing at all for a motion nothing started" do
      app, panel = app_for 12
      mouse app, Action::Motion, 5, 3

      expect(panel.scroll_y).to eq 0
    end
  end

  describe "with nothing attached" do
    it "draws an empty track" do
      root = Panel.new direction: Layout::Direction::Row, height: Sizing.grow
      root.add Scrollbar.new

      expect(Fixtures.render(root, 3, 2)).to eq ["█", "█"]
    end
  end
end
