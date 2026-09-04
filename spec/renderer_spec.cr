require "./spec_helper"

Spectator.describe TermBuf::Widgets::Renderer do
  alias Box = Fixtures::Box
  alias Label = TermBuf::Widgets::Label
  alias Point = Layout::AttachPoint

  describe "a widget in a box" do
    it "draws the border and puts the content inside it" do
      root = Box.new
      root.border = TermBuf::Border.plain
      root.add Label.new("hi")

      expect(Fixtures.render(root, 8, 3)).to eq ["┌──────┐", "│hi    │", "└──────┘"]
    end

    it "puts a title in the top edge" do
      root = Box.new
      root.border = TermBuf::Border.rounded title: "name"
      root.add Label.new("hi")

      expect(Fixtures.render(root, 12, 3).first).to eq "╭─name─────╮"
    end

    it "wraps the content to what the border left it" do
      root = Box.new
      root.border = TermBuf::Border.plain
      root.add Label.new("one two")

      expect(Fixtures.render(root, 7, 4)).to eq ["┌─────┐", "│one  │", "│two  │", "└─────┘"]
    end
  end

  describe "a scroll panel" do
    def scrolled(scroll : Int32) : Array(String)
      root = Box.new
      panel = Box.new
      panel.clip_y = true
      panel.scroll_y = scroll
      panel.height = Sizing.fixed 2
      panel.add Label.new("one"), Label.new("two"), Label.new("three")
      root.add panel, Label.new("out")

      Fixtures.render root, 6, 4
    end

    it "shows the rows the scroll brought into view" do
      expect(scrolled(1)).to eq ["two", "three", "out", ""]
    end

    it "shows the first rows when nothing is scrolled" do
      expect(scrolled(0)).to eq ["one", "two", "out", ""]
    end

    it "cuts what runs past its own edge rather than the screen's" do
      root = Box.new
      panel = Box.new
      panel.clip_x = true
      panel.scroll_x = 2
      panel.width = Sizing.fixed 4
      panel.direction = Layout::Direction::Row
      inner = Label.new "abcdefgh", wrap: Layout::Wrap::None
      inner.width = Sizing.fixed 8
      panel.add inner
      root.direction = Layout::Direction::Row
      root.add panel, Label.new("Z")

      expect(Fixtures.render(root, 6, 1)).to eq ["cdefZ"]
    end
  end

  describe "a float" do
    it "is drawn over the content it covers" do
      root = Box.new
      root.add Label.new("aaaaa")

      over = Label.new "XY"
      over.floating = Layout::Floating.on nil, Point::LeftTop, Point::LeftTop, dx: 1
      root.add over

      expect(Fixtures.render(root, 5, 1)).to eq ["aXYaa"]
    end

    it "is drawn in the order the painting order gives" do
      root = Box.new
      root.add Label.new("....")

      lower = Label.new "ab"
      lower.floating = Layout::Floating.on nil, Point::LeftTop, Point::LeftTop, z: 1
      upper = Label.new "Z"
      upper.floating = Layout::Floating.on nil, Point::LeftTop, Point::LeftTop, dx: 1, z: 2
      root.add lower, upper

      expect(Fixtures.render(root, 4, 1)).to eq ["aZ.."]
    end
  end

  describe "styles" do
    let(ground) { TermBuf::Style::DEFAULT.bg TermBuf::Color.indexed(4_u8) }

    it "reaches a child that never named one" do
      root = Box.new
      root.style = ground
      label = Label.new "hi"
      root.add label

      buffer = Fixtures.painted root, 4, 1
      expect(Fixtures.style_at(buffer, 0, 0).background).to eq ground.background
    end

    it "lets the child add to it without losing it" do
      root = Box.new
      root.style = ground
      label = Label.new "hi"
      label.style = TermBuf::Style::DEFAULT.bold
      root.add label

      painted = Fixtures.style_at Fixtures.painted(root, 4, 1), 0, 0
      expect(painted.background).to eq ground.background
      expect(painted.attributes.bold?).to be_true
    end

    it "paints the ground of a widget that named one, and no further" do
      root = Box.new
      root.direction = Layout::Direction::Row
      panel = Box.new
      panel.style = ground
      panel.width = Sizing.fixed 2
      panel.height = Sizing.fixed 1
      root.add panel, Box.sized(2, 1)

      buffer = Fixtures.painted root, 4, 1
      expect(Fixtures.style_at(buffer, 1, 0).background).to eq ground.background
      expect(Fixtures.style_at(buffer, 2, 0).background).to eq TermBuf::Style::DEFAULT.background
    end
  end

  describe "what it leaves alone" do
    it "draws nothing for a hidden widget" do
      root = Box.new
      shown = Label.new "aa"
      hidden = Label.new "bb"
      hidden.hidden = true
      root.add hidden, shown

      expect(Fixtures.render(root, 4, 2)).to eq ["aa", ""]
    end

    it "draws nothing outside the screen" do
      root = Box.new
      root.direction = Layout::Direction::Row
      wide = Label.new "abcdefgh", wrap: Layout::Wrap::None
      wide.width = Sizing.fixed 8
      root.add wide

      expect(Fixtures.render(root, 4, 1)).to eq ["abcd"]
    end
  end
end
