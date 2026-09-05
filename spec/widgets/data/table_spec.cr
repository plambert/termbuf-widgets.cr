require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Table do
  alias Table = TermBuf::Widgets::Table
  alias Rows = TermBuf::Widgets::Rows
  alias Scrollbar = TermBuf::Widgets::Scrollbar
  alias Align = TermBuf::Unicode::Align
  alias Button = TermBuf::Input::Mouse::Button
  alias Action = TermBuf::Input::Mouse::Action

  # A source that counts how many times it was asked for a row, so a spec can
  # say what the table did rather than how long it took.
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
      "row#{index}"
    end
  end

  # Two fixed columns: six cells of name, a gap, and two of length.
  def table(count : Int32 = 10) : Table(String)
    made = Table.new Rows.of(Array.new(count) { |index| "row#{index}" })
    made.add_column "name", ->(item : String) { item }, Sizing.fixed(6)
    made.add_column "n", ->(item : String) { item.size.to_s }, Sizing.fixed(2)
    made
  end

  def settle(made : Table(String), columns : Int32 = 12, rows : Int32 = 4) : Table(String)
    Layout::Tree.new(made, Rect.full(columns, rows)).layout
    made
  end

  # A table under an app, with a box above it writing down every message.
  def wired(made : Table(String), columns : Int32 = 12,
            rows : Int32 = 4) : {Fixtures::TestApp, Array(TermBuf::Widgets::Message)}
    root = Fixtures::Box.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    seen = [] of TermBuf::Widgets::Message
    root.on_handle = ->(event : TermBuf::Event, _context : TermBuf::Widgets::Context) do
      seen << event if event.is_a? TermBuf::Widgets::Message
      nil
    end
    root.add made

    app = Fixtures::TestApp.new root, columns, rows
    app.frame
    app.focus.focus made

    {app, seen}
  end

  describe "the columns" do
    it "gives a fixed column exactly its cells" do
      expect(settle(table).column_widths).to eq [6, 2]
    end

    it "divides what is left over between the growing ones" do
      made = Table.new Rows.of(%w[a])
      made.add_column "one", ->(item : String) { item }, Sizing.grow
      made.add_column "two", ->(item : String) { item }, Sizing.grow(2)

      expect(settle(made, 13).column_widths).to eq [4, 8]
    end

    it "hands a growing column what a fixed one left" do
      made = Table.new Rows.of(%w[a])
      made.add_column "fixed", ->(item : String) { item }, Sizing.fixed(4)
      made.add_column "rest", ->(item : String) { item }, Sizing.grow

      expect(settle(made, 12).column_widths).to eq [4, 7]
    end

    it "holds a growing column inside its own bounds" do
      made = Table.new Rows.of(%w[a])
      made.add_column "capped", ->(item : String) { item }, Sizing.grow(max: 3)
      made.add_column "rest", ->(item : String) { item }, Sizing.grow

      # What the capped column could not take goes to the one after it, so the
      # columns still come to the nineteen cells the gap left.
      expect(settle(made, 20).column_widths).to eq [3, 16]
    end

    it "fits a column to its own header" do
      made = Table.new Rows.of(%w[a])
      made.add_column "header", ->(item : String) { item }, Sizing.fit
      made.add_column "rest", ->(item : String) { item }, Sizing.grow

      expect(settle(made, 20).column_widths).to eq [6, 13]
    end
  end

  describe "what it draws" do
    it "puts the header over the rows" do
      expect(Fixtures.render(table, 12, 3)).to eq ["name   n", "row0   4", "row1   4"]
    end

    it "leaves the header out when it is told to" do
      made = table
      made.header = false

      expect(Fixtures.render(made, 12, 2)).to eq ["row0   4", "row1   4"]
    end

    it "puts a right-aligned cell at the right of its column" do
      made = Table.new Rows.of(%w[ab])
      made.add_column "n", ->(item : String) { item }, Sizing.fixed(6), align: Align::Right

      expect(Fixtures.render(made, 8, 2)).to eq ["     n", "    ab"]
    end

    it "centres a cell when it is told to" do
      made = Table.new Rows.of(%w[ab])
      made.add_column "n", ->(item : String) { item }, Sizing.fixed(6), align: Align::Center

      expect(Fixtures.render(made, 8, 2)).to eq ["  n", "  ab"]
    end

    it "cuts a cell too wide for its column and says so" do
      made = Table.new Rows.of(["a name nobody sized for"])
      made.add_column "name", ->(item : String) { item }, Sizing.fixed(8)

      expect(Fixtures.render(made, 10, 2)).to eq ["name", "a name …"]
    end

    it "counts a wide cluster as the cells the terminal draws it in" do
      made = Table.new Rows.of(["日本語ですよ"])
      made.add_column "text", ->(item : String) { item }, Sizing.fixed(7)
      made.add_column "after", ->(_item : String) { "|" }, Sizing.fixed(1)

      # Three clusters of two cells and the marker come to seven, so the
      # column after it starts where it was put rather than a cell in. Its own
      # header is wider than it and is cut the same way a cell would be.
      expect(Fixtures.render(made, 10, 2)).to eq ["text    …", "日本語… |"]
    end

    it "reverses the chosen row" do
      buffer = Fixtures.painted table, 12, 3

      expect(Fixtures.style_at(buffer, 0, 1).attributes.reverse?).to be_true
      expect(Fixtures.style_at(buffer, 0, 2).attributes.reverse?).to be_false
    end

    it "draws a cell in what its column said about the row" do
      colour = ->(_item : String) { TermBuf::Style::DEFAULT.bold }
      made = Table.new Rows.of(%w[ab])
      made.add_column "name", ->(item : String) { item }, Sizing.fixed(4), style: colour
      made.selected_style = TermBuf::Style::DEFAULT

      buffer = Fixtures.painted made, 6, 2
      expect(Fixtures.style_at(buffer, 0, 1).attributes.bold?).to be_true
    end

    it "asks only for the rows it is showing" do
      source = Counted.new 100_000
      made = Table.new source
      made.add_column "name", ->(item : String) { item }, Sizing.fixed(6)
      Fixtures.render made, 12, 4

      expect(source.asked).to eq 3
    end

    it "asks for no rows at all to work out how tall it would be" do
      source = Counted.new 500
      made = Table.new source, height: Sizing.fit
      made.add_column "name", ->(item : String) { item }, Sizing.fixed(6)
      Layout::Tree.new(made, Rect.full(12, 4)).layout

      expect(source.asked).to eq 0
    end
  end

  describe "scrolling" do
    it "keeps the header where it is while the rows move" do
      made = table 20
      Fixtures.render made, 12, 4
      made.scroll_by 0, 5

      expect(Fixtures.render(made, 12, 4)).to eq ["name   n", "row5   4", "row6   4", "row7   4"]
    end

    it "counts the rows as its content and the room under the header as the window" do
      made = settle table(20), 12, 4

      expect(made.content_size).to eq({9, 20})
      expect(made.viewport_size).to eq({12, 3})
      expect(made.max_scroll).to eq({0, 17})
    end

    it "scrolls sideways when the columns are wider than it is" do
      made = settle table(3), 6, 3

      expect(made.max_scroll[0]).to eq 3
      expect(Fixtures.render(made, 6, 2)).to eq ["name", "row0"]

      made.scroll_by 3, 0
      expect(Fixtures.render(made, 6, 2)).to eq ["e   n", "0   4"]
    end

    it "brings a column into view without moving further than it must" do
      made = settle table(3), 6, 3
      made.reveal_column 1

      expect(made.offset).to eq 3
    end

    it "answers a wheel notch by scrolling, not by selecting" do
      made = table 20
      app, _ = wired made
      app.events.send TermBuf::Events::Mouse.new(Button::WheelDown, 1, 1,
        TermBuf::Modifiers::None, Action::Press)
      app.pump

      expect(made.scroll).to eq 3
      expect(made.selected).to eq 0
    end
  end

  describe "the selection" do
    it "moves and stops at either end" do
      made = settle table(5)

      made.select 3
      expect(made.selected).to eq 3

      made.select 40
      expect(made.selected).to eq 4

      made.select(-2)
      expect(made.selected).to eq 0
    end

    it "brings itself into view" do
      made = settle table(20), 12, 4
      made.select 9

      expect(made.scroll).to eq 7
      expect(made.visible_range).to eq(7...10)
    end

    it "moves with the keys" do
      made = table 20
      app, _ = wired made

      Fixtures.press app, "Down Down"
      expect(made.selected).to eq 2

      Fixtures.press app, "End"
      expect(made.selected).to eq 19

      Fixtures.press app, "Home"
      expect(made.selected).to eq 0

      Fixtures.press app, "PageDown"
      expect(made.selected).to eq 3
    end

    it "says when it moved" do
      made = table 5
      app, seen = wired made
      Fixtures.press app, "Down"
      app.pump

      expect(seen.map(&.class)).to eq [Table::Selected]
      expect(seen.first.as(Table::Selected).index).to eq 1
    end

    it "says nothing when it did not move" do
      made = table 5
      app, seen = wired made
      Fixtures.press app, "Up"
      app.pump

      expect(seen).to be_empty
    end

    it "says the row was used on Enter" do
      made = table 5
      app, seen = wired made
      made.select 2
      app.pump
      seen.clear

      Fixtures.press app, "Enter"
      app.pump

      expect(seen.map(&.class)).to eq [Table::Activated]
      expect(seen.first.as(Table::Activated).index).to eq 2
    end

    it "answers the row it is on" do
      made = settle table(5)
      made.select 3

      expect(made.current).to eq "row3"
    end

    it "answers nothing when there are no rows" do
      expect(settle(table(0)).current).to be_nil
    end

    it "goes to the row a click landed on" do
      made = table 20
      app, _ = wired made
      app.events.send TermBuf::Events::Mouse.new(Button::Left, 2, 3,
        TermBuf::Modifiers::None, Action::Press)
      app.pump

      expect(made.selected).to eq 2
    end
  end

  describe "with a scrollbar beside it" do
    it "shows how far down the rows it has got" do
      root = TermBuf::Widgets::Panel.new direction: Layout::Direction::Row,
        width: Sizing.grow, height: Sizing.grow
      made = table 16
      bar = Scrollbar.new made
      root.add made, bar

      Layout::Tree.new(root, Rect.full(13, 5)).layout
      expect(bar.thumb_start).to eq 0

      made.select 15
      expect(bar.thumb_start).to be > 0
    end
  end
end
