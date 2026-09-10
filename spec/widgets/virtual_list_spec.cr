require "../spec_helper"

Spectator.describe TermBuf::Widgets::VirtualList do
  alias VirtualList = TermBuf::Widgets::VirtualList
  alias Rows = TermBuf::Widgets::Rows
  alias Panel = TermBuf::Widgets::Panel
  alias Scrollbar = TermBuf::Widgets::Scrollbar
  alias Button = TermBuf::Input::Mouse::Button
  alias Action = TermBuf::Input::Mouse::Action

  # A source that counts how many times it was asked for a row, so a spec can
  # say what the list did rather than how long it took.
  class Counted < Rows(String)
    getter asked = 0
    getter count : Int32

    def initialize(@count : Int32)
    end

    def size : Int32
      @count
    end

    def row(index : Int32) : String
      @asked += 1
      "r#{index}"
    end
  end

  def list(count : Int32) : VirtualList(String)
    VirtualList.new Rows.of(Array.new(count) { |index| "r#{index}" })
  end

  def settle(made : VirtualList(String), columns : Int32 = 6,
             rows : Int32 = 4) : VirtualList(String)
    Layout::Tree.new(made, Rect.full(columns, rows)).layout
    made
  end

  describe "what it draws" do
    it "shows the rows that fit and no others" do
      expect(Fixtures.render(list(10), 6, 3)).to eq ["r0", "r1", "r2"]
    end

    it "shows what it has when that is less than fits" do
      expect(Fixtures.render(list(2), 6, 4)).to eq ["r0", "r1", "", ""]
    end

    it "shows nothing at all when it holds nothing" do
      expect(Fixtures.render(list(0), 6, 2)).to eq ["", ""]
    end

    it "asks only for the rows it is showing" do
      source = Counted.new 100_000
      made = VirtualList.new source
      Fixtures.render made, 6, 4

      expect(source.asked).to eq 4
    end

    it "asks the same of a hundred thousand rows as of ten" do
      big = Counted.new 100_000
      small = Counted.new 10
      Fixtures.render VirtualList.new(big), 6, 4
      Fixtures.render VirtualList.new(small), 6, 4

      expect(big.asked).to eq small.asked
    end

    it "asks for none at all to work out how tall it would be" do
      source = Counted.new 500
      made = VirtualList.new source, height: Sizing.fit
      Layout::Tree.new(made, Rect.full(6, 4)).layout

      expect(source.asked).to eq 0
    end

    it "draws each row through the block it was given" do
      made = list 4
      made.on_draw = ->(view : TermBuf::View, _index : Int32, item : String, chosen : Bool, _focused : Bool) do
        view.write 0, 0, "#{chosen ? '>' : ' '}#{item}"
        nil
      end
      made.select 1

      expect(Fixtures.render(made, 6, 3)).to eq [" r0", ">r1", " r2"]
    end

    it "tells the block whether it has the keyboard" do
      made = list 3
      seen = [] of Bool
      made.on_draw = ->(view : TermBuf::View, _index : Int32, item : String, _chosen : Bool, focused : Bool) do
        seen << focused
        view.write 0, 0, item
        nil
      end

      Fixtures.render made, 6, 1
      expect(seen).to eq [false]

      app = Fixtures::TestApp.new made, 6, 1
      seen.clear
      app.frame

      expect(seen).to eq [true]
    end

    it "reverses the chosen row by default" do
      made = list 3
      made.select 1
      buffer = Fixtures.painted made, 6, 3

      expect(Fixtures.style_at(buffer, 0, 1).attributes.reverse?).to be_true
      expect(Fixtures.style_at(buffer, 0, 0).attributes.reverse?).to be_false
    end
  end

  describe "what it measures" do
    it "counts its rows as the content" do
      made = settle list(20)

      expect(made.content_size).to eq({6, 20})
      expect(made.viewport_size).to eq({6, 4})
      expect(made.max_scroll).to eq({0, 16})
    end

    it "asks for a row for each one it has when it fits itself to them" do
      made = VirtualList.new Rows.of(%w[a b c]), height: Sizing.fit
      root = Panel.new
      root.add made
      Layout::Tree.new(root, Rect.full(6, 8)).layout

      expect(made.rect.height).to eq 3
    end
  end

  describe "the selection" do
    it "starts on the first row" do
      expect(list(5).selected).to eq 0
    end

    it "moves and stops at either end" do
      made = settle list(5)

      made.select 3
      expect(made.selected).to eq 3

      made.select 40
      expect(made.selected).to eq 4

      made.select(-3)
      expect(made.selected).to eq 0
    end

    it "brings itself into view on the way down" do
      made = settle list(20)
      made.select 9

      expect(made.scroll).to eq 6
      expect(made.visible_range).to eq(6...10)
    end

    it "brings itself into view on the way back" do
      made = settle list(20)
      made.select 15
      made.select 2

      expect(made.scroll).to eq 2
    end

    it "answers the row it is on" do
      made = settle list(5)
      made.select 2

      expect(made.current).to eq "r2"
    end

    it "answers nothing when there are no rows" do
      expect(settle(list(0)).current).to be_nil
    end
  end

  describe "the keys" do
    def wired(count : Int32, rows : Int32 = 4) : {Fixtures::TestApp, VirtualList(String)}
      made = VirtualList.new Rows.of(Array.new(count) { |index| "r#{index}" })
      app = Fixtures::TestApp.new made, 6, rows
      app.frame
      app.focus.focus made

      {app, made}
    end

    it "moves down and up" do
      app, made = wired 10
      Fixtures.press app, "Down Down"
      expect(made.selected).to eq 2

      Fixtures.press app, "Up"
      expect(made.selected).to eq 1
    end

    it "moves a window at a time" do
      app, made = wired 20
      Fixtures.press app, "PageDown"
      expect(made.selected).to eq 4

      Fixtures.press app, "PageUp"
      expect(made.selected).to eq 0
    end

    it "goes to either end" do
      app, made = wired 20
      Fixtures.press app, "End"
      expect(made.selected).to eq 19

      Fixtures.press app, "Home"
      expect(made.selected).to eq 0
    end

    it "answers a wheel notch by scrolling, not by selecting" do
      app, made = wired 20
      app.events.send TermBuf::Events::Mouse.new(Button::WheelDown, 1, 1,
        TermBuf::Modifiers::None, Action::Press)
      app.pump

      expect(made.scroll).to eq 3
      expect(made.selected).to eq 0
    end
  end

  describe "when the window changes size" do
    it "keeps the selection showing" do
      made = list 20
      app = Fixtures::TestApp.new made, 6, 8
      app.frame
      made.select 7
      app.frame
      expect(made.scroll).to eq 0

      app.resized 6, 3
      app.pump
      app.frame

      expect(made.visible_range.includes? 7).to be_true
    end

    it "leaves a scroll somebody asked for alone" do
      made = list 20
      app = Fixtures::TestApp.new made, 6, 4
      app.frame
      made.scroll_by 0, 8
      app.frame

      expect(made.scroll).to eq 8
    end
  end

  describe "with a scrollbar beside it" do
    it "shows how far down the rows it has got" do
      root = Panel.new direction: Layout::Direction::Row,
        width: Sizing.grow, height: Sizing.grow
      made = VirtualList.new Rows.of(Array.new(16) { |index| "r#{index}" })
      bar = Scrollbar.new made
      root.add made, bar

      Layout::Tree.new(root, Rect.full(6, 4)).layout
      expect(bar.thumb_size).to eq 1
      expect(bar.thumb_start).to eq 0

      made.select 15
      expect(bar.thumb_start).to eq 3
    end
  end

  describe "a source that is asked rather than held" do
    it "answers from the blocks it was given" do
      made = VirtualList.new Rows.from(-> { 1_000 }, ->(index : Int32) { "row #{index}" })
      expect(Fixtures.render(made, 8, 2)).to eq ["row 0", "row 1"]
    end
  end
end
