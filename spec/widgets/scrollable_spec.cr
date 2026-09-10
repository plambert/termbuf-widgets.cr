require "../spec_helper"

Spectator.describe TermBuf::Widgets::Scrollable do
  alias Scrollable = TermBuf::Widgets::Scrollable
  alias Panel = TermBuf::Widgets::Panel
  alias Label = TermBuf::Widgets::Label

  # A scrollable holding *count* one-row labels, laid out at *columns* by
  # *rows*, and the labels.
  def stack(count : Int32, columns : Int32 = 6, rows : Int32 = 3) : {Scrollable, Array(Label)}
    panel = Scrollable.new
    labels = Array.new(count) { |index| Label.new "row#{index}" }
    labels.each { |label| panel.add label }
    Layout::Tree.new(panel, Rect.full(columns, rows)).layout

    {panel, labels}
  end

  describe "clipping" do
    it "leaves its children the size they asked for" do
      panel, labels = stack 5

      expect(labels.map(&.rect.height)).to eq [1, 1, 1, 1, 1]
      expect(panel.clip_y?).to be_true
    end

    it "clips left and right when it is a row" do
      panel = Scrollable.new direction: Layout::Direction::Row

      expect(panel.clip_x?).to be_true
      expect(panel.clip_y?).to be_false
    end

    it "clips whichever axes it was told to" do
      panel = Scrollable.new clip_x: true, clip_y: true

      expect(panel.clip_x?).to be_true
      expect(panel.clip_y?).to be_true
    end

    it "shows only what is in the window" do
      panel, _ = stack 5
      expect(Fixtures.render(panel, 6, 3)).to eq ["row0", "row1", "row2"]
    end
  end

  describe "what it measures" do
    it "counts the content, not the window" do
      panel, _ = stack 5

      expect(panel.content_size).to eq({4, 5})
      expect(panel.viewport_size).to eq({6, 3})
      expect(panel.max_scroll).to eq({0, 2})
    end

    it "counts nothing at all when it holds nothing" do
      panel = Scrollable.new
      Layout::Tree.new(panel, Rect.full(6, 3)).layout

      expect(panel.content_size).to eq({0, 0})
      expect(panel.max_scroll).to eq({0, 0})
    end

    it "counts the same however far it is scrolled" do
      panel, _ = stack 8
      before = panel.content_size
      panel.scroll_by dy: 4

      expect(panel.content_size).to eq before
    end
  end

  describe "#scroll_by" do
    it "moves the window" do
      panel, _ = stack 5
      panel.scroll_by dy: 2

      expect(Fixtures.render(panel, 6, 3)).to eq ["row2", "row3", "row4"]
    end

    it "stops at the end of the content" do
      panel, _ = stack 5
      panel.scroll_by dy: 40

      expect(panel.scroll_y).to eq 2
    end

    it "stops at the start" do
      panel, _ = stack 5
      panel.scroll_by dy: -40

      expect(panel.scroll_y).to eq 0
    end

    it "leaves an axis it does not clip alone" do
      panel, _ = stack 5
      panel.scroll_by dx: 3

      expect(panel.scroll_x).to eq 0
    end
  end

  describe "#scroll_to" do
    it "brings a widget below the window up into it" do
      panel, labels = stack 8
      panel.scroll_to labels[6]

      expect(panel.scroll_y).to eq 4
    end

    it "brings one above the window down into it" do
      panel, labels = stack 8
      panel.scroll_by dy: 5
      panel.scroll_to labels[1]

      expect(panel.scroll_y).to eq 1
    end

    it "leaves the window alone for one already in it" do
      panel, labels = stack 8
      panel.scroll_by dy: 3
      panel.scroll_to labels[4]

      expect(panel.scroll_y).to eq 3
    end

    it "shows the start of something too large to fit" do
      panel = Scrollable.new
      tall = Label.new "a\nb\nc\nd\ne", wrap: Layout::Wrap::None
      panel.add Label.new("head"), tall
      Layout::Tree.new(panel, Rect.full(6, 2)).layout

      panel.scroll_to tall
      expect(panel.scroll_y).to eq 1
    end
  end

  describe "the wheel" do
    def wired : {Fixtures::TestApp, Scrollable}
      panel = Scrollable.new
      8.times { |index| panel.add Label.new("row#{index}") }
      app = Fixtures::TestApp.new panel, 6, 3
      app.frame

      {app, panel}
    end

    def wheel(app : Fixtures::TestApp, button : TermBuf::Input::Mouse::Button,
              x : Int32 = 1, y : Int32 = 1) : Nil
      app.events.send TermBuf::Events::Mouse.new(button, x, y, TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)
      app.pump
    end

    it "moves the window down a notch" do
      app, panel = wired
      wheel app, TermBuf::Input::Mouse::Button::WheelDown

      expect(panel.scroll_y).to eq 3
    end

    it "moves it back up" do
      app, panel = wired
      panel.scroll_by dy: 5
      wheel app, TermBuf::Input::Mouse::Button::WheelUp

      expect(panel.scroll_y).to eq 2
    end

    it "leaves a click alone" do
      app, panel = wired
      wheel app, TermBuf::Input::Mouse::Button::Left

      expect(panel.scroll_y).to eq 0
    end
  end

  describe "the keyboard" do
    # A scroll panel over *count* labels, laid out and drawn once so that the
    # window has a size to page by.
    def keyed(count : Int32, columns : Int32 = 6, rows : Int32 = 3) : {Fixtures::TestApp, Scrollable}
      panel = Scrollable.new
      count.times { |index| panel.add Label.new("row#{index}") }
      app = Fixtures::TestApp.new panel, columns, rows
      app.frame

      {app, panel}
    end

    it "takes the keyboard when nothing in it can" do
      panel, _ = stack 5

      expect(panel.focusable?).to be_true
    end

    it "leaves the keyboard to a control inside it" do
      panel = Scrollable.new
      panel.add Label.new("row"), TermBuf::Widgets::Button.new("press me")

      expect(panel.focusable?).to be_false
    end

    it "counts a control buried under a plain widget" do
      panel = Scrollable.new
      holder = Panel.new
      holder.add TermBuf::Widgets::Button.new("press me")
      panel.add holder

      expect(panel.focusable?).to be_false
    end

    it "ignores a control inside a hidden widget, the way the ring does" do
      panel = Scrollable.new
      holder = Panel.new
      holder.add TermBuf::Widgets::Button.new("press me")
      holder.hidden = true
      panel.add holder

      expect(panel.focusable?).to be_true
    end

    it "moves the window a row at a time" do
      app, panel = keyed 8
      Fixtures.press app, "Down"

      expect(panel.scroll_y).to eq 1
    end

    it "moves it back a row" do
      app, panel = keyed 8
      panel.scroll_by dy: 4
      Fixtures.press app, "Up"

      expect(panel.scroll_y).to eq 3
    end

    it "moves a window at a time on the page keys" do
      app, panel = keyed 12
      Fixtures.press app, "PageDown"

      expect(panel.scroll_y).to eq 3
    end

    it "goes to the ends on Home and End" do
      app, panel = keyed 8
      Fixtures.press app, "End"
      expect(panel.scroll_y).to eq 5

      Fixtures.press app, "Home"
      expect(panel.scroll_y).to eq 0
    end

    it "moves a column at a time when it clips sideways" do
      panel = Scrollable.new direction: Layout::Direction::Row
      4.times { |index| panel.add Label.new("row#{index}") }
      app = Fixtures::TestApp.new panel, 6, 3
      app.frame

      Fixtures.press app, "Right"
      expect(panel.scroll_x).to eq 1
    end

    it "leaves Left and Right alone on an axis it does not clip" do
      app, panel = keyed 8
      taken = app.router.dispatch TermBuf::Events::Key.new(TermBuf::Key.parse("Right").first,
        Bytes.empty)

      expect(taken).to be_false
      expect(panel.scroll_x).to eq 0
    end
  end

  describe "what it tells the surface" do
    it "leaves a scroll hint when the window moved" do
      panel, _ = stack 8
      buffer = TermBuf::Buffer.new 6, 3
      tree = Layout::Tree.new panel, Rect.full(6, 3)
      tree.layout_if_needed
      surface = TermBuf::BufferSurface.new buffer

      TermBuf::Widgets::Renderer.render tree, surface
      expect(buffer.scroll_hints).to be_empty

      panel.scroll_by dy: 2
      tree.layout_if_needed
      TermBuf::Widgets::Renderer.render tree, surface

      expect(buffer.scroll_hints.size).to eq 1
      expect(buffer.scroll_hints.first.lines).to eq 2
      expect(buffer.scroll_hints.first.rect).to eq Rect.new(0, 0, 6, 3)
    end

    it "leaves none when the window stayed put" do
      panel, _ = stack 8
      buffer = TermBuf::Buffer.new 6, 3
      tree = Layout::Tree.new panel, Rect.full(6, 3)
      tree.layout_if_needed
      surface = TermBuf::BufferSurface.new buffer

      TermBuf::Widgets::Renderer.render tree, surface
      TermBuf::Widgets::Renderer.render tree, surface

      expect(buffer.scroll_hints).to be_empty
    end
  end
end
