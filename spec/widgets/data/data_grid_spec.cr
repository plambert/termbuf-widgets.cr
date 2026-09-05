require "../../spec_helper"

Spectator.describe TermBuf::Widgets::DataGrid do
  alias DataGrid = TermBuf::Widgets::DataGrid
  alias Rows = TermBuf::Widgets::Rows
  alias Button = TermBuf::Input::Mouse::Button
  alias Action = TermBuf::Input::Mouse::Action

  # Three fixed columns of four cells each, so a click lands somewhere a spec
  # can name.
  def grid(items : Array(String) = %w[alpha bravo charlie delta]) : DataGrid(String)
    made = DataGrid.new Rows.of(items)
    made.add_column "one", ->(item : String) { item[0].to_s }, Sizing.fixed(4)
    made.add_column "two", ->(item : String) { item[1].to_s }, Sizing.fixed(4)
    made.add_column "all", ->(item : String) { item }, Sizing.fixed(4)
    made
  end

  def settle(made : DataGrid(String), columns : Int32 = 14,
             rows : Int32 = 5) : DataGrid(String)
    Layout::Tree.new(made, Rect.full(columns, rows)).layout
    made
  end

  # A grid under an app, with a box above it writing down every message.
  def wired(made : DataGrid(String), columns : Int32 = 14,
            rows : Int32 = 5) : {Fixtures::TestApp, Array(TermBuf::Widgets::Message)}
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

  describe "the focused cell" do
    it "starts on the first column" do
      expect(grid.focused_column).to eq 0
    end

    it "moves with Left and Right and stops at either end" do
      made = grid
      app, _ = wired made

      Fixtures.press app, "Right Right"
      expect(made.focused_column).to eq 2

      Fixtures.press app, "Right"
      expect(made.focused_column).to eq 2

      Fixtures.press app, "Left Left Left"
      expect(made.focused_column).to eq 0
    end

    it "brings the column it moved to into view" do
      made = settle grid, 8
      made.focus_column 2

      expect(made.offset).to eq 6
    end

    it "draws the focused cell apart from the rest of the row" do
      made = grid
      made.selection = DataGrid::Selection::Cell
      made.focus_column 1
      buffer = Fixtures.painted made, 14, 3

      expect(Fixtures.style_at(buffer, 5, 1).attributes.reverse?).to be_true
      expect(Fixtures.style_at(buffer, 0, 1).attributes.reverse?).to be_false
    end

    it "reverses the whole row instead when it selects rows" do
      made = grid
      buffer = Fixtures.painted made, 14, 3

      expect(Fixtures.style_at(buffer, 0, 1).attributes.reverse?).to be_true
      expect(Fixtures.style_at(buffer, 5, 1).attributes.reverse?).to be_true
    end

    it "goes to the column a click landed in" do
      made = grid
      app, _ = wired made
      app.events.send TermBuf::Events::Mouse.new(Button::Left, 6, 2,
        TermBuf::Modifiers::None, Action::Press)
      app.pump

      expect(made.focused_column).to eq 1
      expect(made.selected).to eq 1
    end
  end

  describe "sorting" do
    it "puts the rows in the order the column says" do
      made = grid %w[delta alpha charlie bravo]
      made.sort_by 2

      expect((0...4).map { |index| made.row_at index }).to eq %w[alpha bravo charlie delta]
    end

    it "turns the order around" do
      made = grid %w[delta alpha charlie bravo]
      made.sort_by 2, DataGrid::Order::Descending

      expect((0...4).map { |index| made.row_at index }).to eq %w[delta charlie bravo alpha]
    end

    it "keeps rows whose cells compare equal in the order the source had them" do
      made = grid %w[b1 a1 b2 a2]
      made.sort_by 0

      expect((0...4).map { |index| made.row_at index }).to eq %w[a1 a2 b1 b2]

      made.sort_by 0, DataGrid::Order::Descending
      expect((0...4).map { |index| made.row_at index }).to eq %w[b1 b2 a1 a2]
    end

    it "maps screen order onto source order both ways" do
      made = grid %w[delta alpha charlie bravo]
      made.sort_by 2

      expect((0...4).map { |index| made.source_index index }).to eq [1, 3, 2, 0]
      expect(made.screen_index(0)).to eq 3
    end

    it "leaves the source alone" do
      items = %w[delta alpha charlie bravo]
      made = grid items
      made.sort_by 2

      expect(items).to eq %w[delta alpha charlie bravo]
      expect(made.rows.row(0)).to eq "delta"
    end

    it "keeps the selection on the row it was on" do
      made = settle grid(%w[delta alpha charlie bravo])
      made.select 0
      made.sort_by 2

      expect(made.selected).to eq 3
      expect(made.current).to eq "delta"
    end

    it "puts the rows back the way they were" do
      made = grid %w[delta alpha]
      made.sort_by 2
      made.clear_sort

      expect(made.row_at(0)).to eq "delta"
      expect(made.sort_column).to be_nil
    end

    it "turns the sort around on a second press of the key" do
      made = grid %w[delta alpha]
      app, _ = wired made

      Fixtures.type app, "s"
      expect(made.sort_direction.ascending?).to be_true
      expect(made.row_at(0)).to eq "alpha"

      Fixtures.type app, "s"
      expect(made.sort_direction.descending?).to be_true
      expect(made.row_at(0)).to eq "delta"
    end

    it "sorts by the column whose header was clicked" do
      made = grid %w[ba ab]
      app, _ = wired made
      app.events.send TermBuf::Events::Mouse.new(Button::Left, 5, 0,
        TermBuf::Modifiers::None, Action::Press)
      app.pump

      expect(made.sort_column).to eq 1
      expect(made.row_at(0)).to eq "ba"
      expect(made.selected).to eq 0
    end

    it "refuses a column that is not there" do
      expect { grid.sort_by 9 }.to raise_error IndexError
    end
  end

  describe "picking more than one row" do
    it "answers the row it is on when it selects rows" do
      made = settle grid
      made.select 2

      expect(made.selected_indices).to eq [2]
    end

    it "answers nothing at all when there are no rows" do
      expect(settle(grid(%w[])).selected_indices).to be_empty
    end

    it "toggles a row in and out with the space bar" do
      made = grid
      made.selection = DataGrid::Selection::Multi
      app, _ = wired made

      Fixtures.type app, " "
      Fixtures.press app, "Down Down"
      Fixtures.type app, " "
      expect(made.selected_indices).to eq [0, 2]

      Fixtures.type app, " "
      expect(made.selected_indices).to eq [0]
    end

    it "keeps what was picked when the rows are sorted under it" do
      made = grid %w[delta alpha charlie bravo]
      made.selection = DataGrid::Selection::Multi
      settle made
      made.toggle 0
      made.sort_by 2

      expect(made.selected_indices).to eq [0]
      expect(made.row_at(3)).to eq "delta"
    end

    it "draws every picked row as chosen" do
      made = grid
      made.selection = DataGrid::Selection::Multi
      settle made
      made.toggle 2
      buffer = Fixtures.painted made, 14, 5

      expect(Fixtures.style_at(buffer, 0, 3).attributes.reverse?).to be_true
      expect(Fixtures.style_at(buffer, 0, 2).attributes.reverse?).to be_false
    end
  end

  describe "editing a cell" do
    it "opens an editor over the focused cell" do
      made = grid
      app, _ = wired made
      Fixtures.press app, "Enter"
      app.frame

      expect(made.editing?).to be_true
      expect(app.focused).to eq made.field
      expect(app.lines[1].starts_with? "a").to be_true
    end

    it "says what was typed when the edit is committed" do
      made = grid
      app, seen = wired made
      made.focus_column 2
      Fixtures.press app, "Enter"
      Fixtures.type app, "!"
      Fixtures.press app, "Enter"
      app.pump
      app.pump

      edits = seen.select DataGrid::Edited
      expect(edits.size).to eq 1
      expect(edits.first.text).to eq "alpha!"
      expect(edits.first.row).to eq 0
      expect(edits.first.column).to eq 2
    end

    it "says nothing at all when the edit is abandoned" do
      made = grid
      app, seen = wired made
      Fixtures.press app, "Enter"
      Fixtures.type app, "!"
      Fixtures.press app, "Escape"
      app.pump
      app.pump

      expect(seen.select DataGrid::Edited).to be_empty
      expect(made.editing?).to be_false
    end

    it "gives the keyboard back to the grid when the editor closes" do
      made = grid
      app, _ = wired made
      Fixtures.press app, "Enter"
      Fixtures.press app, "Escape"
      app.pump

      expect(app.focused).to eq made
      expect(made.children).to be_empty
    end

    it "keeps the grid's own keys out of the way while the editor has them" do
      made = grid
      app, _ = wired made
      Fixtures.press app, "Enter"
      Fixtures.press app, "Down"

      expect(made.selected).to eq 0
      expect(made.field.try &.text).to eq "a"
    end

    it "reports the row the source has rather than the row on screen" do
      made = grid %w[delta alpha]
      app, seen = wired made
      made.sort_by 2
      made.select 0
      Fixtures.press app, "Enter"
      Fixtures.press app, "Enter"
      app.pump
      app.pump

      expect(seen.select(DataGrid::Edited).first.row).to eq 1
    end

    it "uses the row instead when it is told it cannot be edited" do
      made = grid
      made.editable = false
      app, seen = wired made
      Fixtures.press app, "Enter"
      app.pump

      expect(made.editing?).to be_false
      expect(seen.select TermBuf::Widgets::Table::Activated).to_not be_empty
    end
  end
end
