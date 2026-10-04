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

  describe "the scroll margin" do
    alias Margin = TermBuf::Widgets::Scrolls::Margin

    # The first row showing after the selection has been moved to each of
    # *steps* in turn, which is how a key moves it.
    def tops(made : VirtualList(String), steps : Enumerable(Int32)) : Array(Int32)
      steps.map do |index|
        made.select index
        made.scroll
      end
    end

    it "is none until it is asked for" do
      expect(list(3).scroll_margin).to eq Margin.none
    end

    it "leaves the selection on the last row when there is none" do
      made = settle list(30), 6, 10
      made.select 9
      expect(made.scroll).to eq 0

      made.select 10
      expect(made.scroll).to eq 1
      expect(made.visible_range).to eq(1...11)
    end

    it "brings the selection back to the first row when there is none" do
      made = settle list(30), 6, 10
      made.select 20
      made.select 15
      expect(made.scroll).to eq 11

      made.select 10
      expect(made.scroll).to eq 10
    end

    it "stops the window two rows before the bottom when moving down" do
      made = settle list(30), 6, 10
      made.scroll_margin = Margin.rows(2)

      expect(tops(made, 0..7)).to eq [0] * 8
      expect(tops(made, 8..11)).to eq [1, 2, 3, 4]
      expect(made.visible_range).to eq(4...14)
      expect(made.selected).to eq 11
    end

    it "stops the window two rows before the top when moving up" do
      made = settle list(30), 6, 10
      made.scroll_margin = Margin.rows(2)
      made.select 25
      made.select 22

      expect(made.visible_range).to eq(18...28)
      expect(tops(made, [21, 20, 19])).to eq [18, 18, 17]
      expect(made.selected).to eq 19
    end

    it "holds the selection in the middle half with a share of a quarter" do
      made = settle list(60), 6, 20
      made.scroll_margin = Margin.share(0.25)

      expect(made.scroll_margin.rows_for(20)).to eq 5
      (0..40).each do |index|
        made.select index
        row = index - made.scroll
        expect(row).to be < 15
        expect(row).to be >= Math.min(index, 5)
      end
      expect(made.selected - made.scroll).to eq 14
    end

    it "lets the selection reach the first row, because there is nothing above it" do
      made = settle list(30), 6, 10
      made.scroll_margin = Margin.rows(2)
      made.select 20
      made.select 0

      expect(made.scroll).to eq 0
      expect(made.selected).to eq 0
    end

    it "lets the selection reach the last row, because there is nothing below it" do
      made = settle list(30), 6, 10
      made.scroll_margin = Margin.rows(2)
      made.select 29

      expect(made.scroll).to eq 20
      expect(made.visible_range).to eq(20...30)
    end

    it "gives way when the list is shorter than the window needs" do
      made = settle list(8), 6, 10
      made.scroll_margin = Margin.share(0.25)
      made.select 7

      expect(made.scroll).to eq 0
    end

    it "leaves the window alone when the selection is far enough in" do
      made = settle list(30), 6, 10
      made.scroll_margin = Margin.rows(2)
      made.select 12
      made.select 13

      expect(made.scroll).to eq 6
      made.select 8
      expect(made.scroll).to eq 6
    end

    it "does not move what scrolls by an amount or to a row" do
      made = settle list(30), 6, 10
      made.scroll_margin = Margin.rows(2)

      made.scroll_to_row 12
      expect(made.scroll).to eq 12
      made.scroll_by 0, -2
      expect(made.scroll).to eq 10
    end

    it "does not move the wheel's idea of the top" do
      made = settle list(30), 6, 10
      made.scroll_margin = Margin.share(0.5)
      made.scroll_wheel TermBuf::Events::Mouse.new(Button::WheelDown, 1, 1,
        TermBuf::Modifiers::None, Action::Press)

      expect(made.scroll).to eq 3
    end

    it "gives a window of one row no margin" do
      made = settle list(10), 6, 1
      made.scroll_margin = Margin.share(0.5)
      made.select 4

      expect(made.scroll).to eq 4
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

  describe "measuring its width" do
    let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }

    def measured(made : VirtualList(String)) : VirtualList(String)
      made.on_measure = ->(row : String) { row }
      made
    end

    it "is one cell wide without a block to measure with" do
      expect(list(3).intrinsic_width(policy)).to eq Layout::Intrinsic.new(1, 1)
    end

    it "asks for no rows without a block to measure with" do
      source = Counted.new 50
      VirtualList.new(source).intrinsic_width policy

      expect(source.asked).to eq 0
    end

    it "prefers the widest row's text" do
      made = measured VirtualList.new(Rows.of(["ab", "abcdef", "abc"]))

      expect(made.intrinsic_width(policy)).to eq Layout::Intrinsic.new(1, 6)
    end

    it "measures under the policy it is handed" do
      made = measured VirtualList.new(Rows.of(["日本", "abc"]))

      expect(made.intrinsic_width(policy).preferred).to eq 4
    end

    it "measures the text the block answers, not the row" do
      made = VirtualList.new Rows.of([{"rust", 3}, {"crystal", 12}])
      made.on_measure = ->(tag : {String, Int32}) { "#{tag[0]}  #{tag[1]}" }

      expect(made.intrinsic_width(policy).preferred).to eq 11
    end

    it "stays one cell wide when it holds nothing" do
      made = measured VirtualList.new(Rows.of([] of String))

      expect(made.intrinsic_width(policy)).to eq Layout::Intrinsic.new(1, 1)
    end

    it "is as wide as its widest row when sized to fit" do
      made = measured VirtualList.new(Rows.of(["ab", "abcdef"]), width: Sizing.fit)
      root = Fixtures::Box.new
      root.add made
      Layout::Tree.new(root, Rect.full(20, 4)).layout

      expect(made.rect.width).to eq 6
    end

    it "measures once and keeps the answer" do
      source = Counted.new 10
      made = VirtualList.new(source).tap(&.on_measure=(->(row : String) { row }))
      made.intrinsic_width policy
      made.intrinsic_width policy

      expect(source.asked).to eq 10
    end

    it "measures again under a different policy" do
      source = Counted.new 10
      made = VirtualList.new(source).tap(&.on_measure=(->(row : String) { row }))
      made.intrinsic_width policy
      made.intrinsic_width policy.copy_with(ambiguous: 2)

      expect(source.asked).to eq 20
    end

    it "measures again when it is given new rows" do
      made = measured list(2)
      expect(made.intrinsic_width(policy).preferred).to eq 2

      made.rows = Rows.of ["a much longer row"]
      expect(made.intrinsic_width(policy).preferred).to eq 17
    end

    it "measures again when it is given a new block" do
      made = measured list(2)
      expect(made.intrinsic_width(policy).preferred).to eq 2

      made.on_measure = ->(row : String) { row * 3 }
      expect(made.intrinsic_width(policy).preferred).to eq 6
    end

    it "measures again when the number of rows changes" do
      items = ["ab"]
      made = measured VirtualList.new(Rows.of(items))
      expect(made.intrinsic_width(policy).preferred).to eq 2

      items << "abcd"
      expect(made.intrinsic_width(policy).preferred).to eq 4
    end

    it "keeps the old answer for a row changed in place until told" do
      items = ["ab"]
      made = measured VirtualList.new(Rows.of(items))
      made.intrinsic_width policy

      items[0] = "abcd"
      expect(made.intrinsic_width(policy).preferred).to eq 2

      made.remeasure
      expect(made.intrinsic_width(policy).preferred).to eq 4
    end

    it "lays the tree out again when the block changes" do
      made = list 2
      tree = Layout::Tree.new made, Rect.full(6, 4)
      tree.layout

      made.on_measure = ->(row : String) { row }
      expect(tree.dirty?).to be_true
    end

    it "lays the tree out again on new rows or a remeasure, once it measures" do
      made = measured list(2)
      tree = Layout::Tree.new made, Rect.full(6, 4)
      tree.layout

      made.rows = Rows.of ["x"]
      expect(tree.dirty?).to be_true
      tree.layout

      made.remeasure
      expect(tree.dirty?).to be_true
    end

    it "leaves the tree alone on new rows when it does not measure" do
      made = list 2
      tree = Layout::Tree.new made, Rect.full(6, 4)
      tree.layout

      made.rows = Rows.of ["x"]
      expect(tree.dirty?).to be_false
    end

    it "measures no more rows than its limit" do
      source = Counted.new 100_000
      made = VirtualList.new(source).tap(&.on_measure=(->(row : String) { row }))
      made.intrinsic_width policy

      expect(made.measure_limit).to eq 1_000
      expect(source.asked).to eq 1_000
    end

    it "leaves a wider row past the limit out of the width" do
      made = measured VirtualList.new(Rows.of(["ab", "abc", "a much longer row"]))
      made.measure_limit = 2

      expect(made.intrinsic_width(policy).preferred).to eq 3
    end

    it "measures again when the limit changes" do
      made = measured VirtualList.new(Rows.of(["ab", "abc", "a much longer row"]))
      made.measure_limit = 2
      made.intrinsic_width policy

      made.measure_limit = 3
      expect(made.intrinsic_width(policy).preferred).to eq 17
    end

    it "refuses a negative limit" do
      expect { list(1).measure_limit = -1 }.to raise_error(ArgumentError, /negative/)
    end
  end
end
