require "../spec_helper"

Spectator.describe TermBuf::Widgets::Border do
  alias Box = Fixtures::Box
  alias Border = TermBuf::Widgets::Border

  # A box the size of the screen, drawn with *border* around it.
  def boxed(border : Border, columns : Int32, rows : Int32) : Array(String)
    root = Box.new
    root.border = border

    Fixtures.render root, columns, rows
  end

  it "closes the box on all four sides" do
    expect(boxed(Border.plain, 6, 3)).to eq ["┌────┐", "│    │", "└────┘"]
  end

  it "puts a title in the top edge" do
    expect(boxed(Border.rounded(title: "name"), 12, 3).first).to eq "╭─name─────╮"
  end

  it "trims a title that will not fit, at a cluster boundary" do
    expect(boxed(Border.plain(title: "漢字漢字"), 8, 3).first).to eq "┌─漢字─┐"
  end

  it "leaves room for what it surrounds" do
    expect(Border.inset(TermBuf::Rect.new(2, 3, 10, 4))).to eq TermBuf::Rect.new(3, 4, 8, 2)
  end

  it "draws each of the five sets of glyphs" do
    expect(boxed(Border.heavy, 4, 3).first).to eq "┏━━┓"
    expect(boxed(Border.double, 4, 3).first).to eq "╔══╗"
    expect(boxed(Border.ascii, 4, 3).first).to eq "+--+"
  end

  describe "as a layout property" do
    it "takes a cell from every side of what it surrounds" do
      root = Box.new
      root.border = Border.plain
      label = TermBuf::Widgets::Label.new "hi"
      root.add label

      Layout::Tree.new(root, Rect.full(10, 3)).layout
      expect(root.content).to eq Rect.new(1, 1, 8, 1)
      expect(label.rect).to eq Rect.new(1, 1, 2, 1)
    end

    it "adds two cells to what the widget asks for" do
      root = Box.new
      root.direction = Layout::Direction::Row
      boxed = Box.new
      boxed.border = Border.plain
      boxed.add TermBuf::Widgets::Label.new("hi")
      root.add boxed

      Layout::Tree.new(root, Rect.full(20, 5)).layout
      expect(boxed.min_width).to eq 4
    end

    it "wraps what it holds to the room it left" do
      root = Box.new
      root.border = Border.plain
      root.add TermBuf::Widgets::Label.new("one two")

      expect(Fixtures.render(root, 7, 4)).to eq ["┌─────┐", "│one  │", "│two  │", "└─────┘"]
    end

    it "keeps what a widget draws inside its own box" do
      root = Box.new
      root.border = Border.plain
      root.mark = "ab"

      expect(Fixtures.render(root, 6, 3)).to eq ["┌────┐", "│ab  │", "└────┘"]
    end
  end
end
