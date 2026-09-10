require "../spec_helper"

Spectator.describe TermBuf::Widgets::Panel do
  alias Panel = TermBuf::Widgets::Panel
  alias Label = TermBuf::Widgets::Label

  it "lays its children out the way it was told to" do
    root = Panel.new direction: Layout::Direction::Row, gap: 1
    root.add Label.new("ab"), Label.new("cd")

    expect(Fixtures.render(root, 8, 1)).to eq ["ab cd"]
  end

  it "draws nothing of its own" do
    expect(Fixtures.render(Panel.new, 4, 2)).to eq ["", ""]
  end

  it "carries a border and a ground like anything else" do
    root = Panel.new border: TermBuf::Widgets::Border.plain
    root.add Label.new("hi")

    expect(Fixtures.render(root, 6, 3)).to eq ["┌────┐", "│hi  │", "└────┘"]
  end

  it "takes the sizing it was built with" do
    root = Panel.new width: Sizing.grow, height: Sizing.grow
    inner = Panel.new width: Sizing.fixed(3), height: Sizing.fixed(2)
    root.add inner

    Layout::Tree.new(root, Rect.full(10, 4)).layout
    expect(root.rect).to eq Rect.new(0, 0, 10, 4)
    expect(inner.rect).to eq Rect.new(0, 0, 3, 2)
  end

  describe "a margin" do
    it "holds cells around the outside of what the panel draws" do
      root = Panel.new
      inner = Panel.new margin: Layout::Padding.all(1), width: Sizing.grow,
        border: TermBuf::Widgets::Border.plain
      inner.add Label.new("hi")
      root.add inner

      expect(Fixtures.render(root, 8, 5)).to eq ["", " ┌────┐", " │hi  │", " └────┘", ""]
    end

    it "is the outermost part of the inset" do
      panel = Panel.new margin: Layout::Padding.all(1),
        padding: Layout::Padding.all(1), border: TermBuf::Widgets::Border.plain
      Layout::Tree.new(panel, Rect.full(20, 10)).layout

      expect(panel.rect).to eq Rect.new(0, 0, 20, 10)
      expect(panel.frame).to eq Rect.new(1, 1, 18, 8)
      expect(panel.content).to eq Rect.new(3, 3, 14, 4)
    end

    it "counts towards the size the panel asks for" do
      root = Panel.new direction: Layout::Direction::Row
      inner = Panel.new margin: Layout::Padding.all(2)
      inner.add Label.new("ab")
      root.add inner

      Layout::Tree.new(root, Rect.full(20, 10)).layout
      expect(inner.rect.width).to eq 6
      expect(inner.frame.width).to eq 2
    end

    it "does not collapse against a sibling's" do
      root = Panel.new direction: Layout::Direction::Row
      first = Panel.new margin: Layout::Padding.new(0, 1, 0, 0)
      first.add Label.new("a")
      second = Panel.new margin: Layout::Padding.new(0, 0, 0, 1)
      second.add Label.new("b")
      root.add first, second

      expect(Fixtures.render(root, 8, 1)).to eq ["a  b"]
    end

    it "is not part of what a point hits" do
      root = Panel.new width: Sizing.grow, height: Sizing.grow
      inner = Panel.new margin: Layout::Padding.all(1),
        width: Sizing.fixed(6), height: Sizing.fixed(5)
      root.add inner

      tree = Layout::Tree.new root, Rect.full(10, 6)
      tree.layout

      expect(tree.hit(2, 2)).to be inner
      expect(tree.hit(0, 0)).to be root
    end
  end

  describe "a picture" do
    let(pixels) { Bytes[255, 0, 0] }
    let(image) { TermBuf::Image.rgb(pixels, 1, 1) }

    def store : TermBuf::ImageStore
      TermBuf::ImageStore.new TermBuf::Capabilities::NONE
    end

    it "asks for one across the box the panel draws in" do
      panel = Panel.new image: image
      images = store
      Fixtures.render panel, 10, 4, images: images

      expect(images.placements.size).to eq 1
      expect(images.placements.first.bounds).to eq Rect.new(0, 0, 10, 4)
    end

    it "puts it under the text by default" do
      panel = Panel.new image: image
      images = store
      Fixtures.render panel, 6, 2, images: images

      expect(images.placements.first.under_text?).to be_true
    end

    it "puts it over the text when it is asked to" do
      panel = Panel.new image: image, image_z: 1
      images = store
      Fixtures.render panel, 6, 2, images: images

      expect(images.placements.first.under_text?).to be_false
    end

    it "leaves the margin out of it" do
      panel = Panel.new image: image, margin: Layout::Padding.all(1)
      images = store
      Fixtures.render panel, 10, 4, images: images

      expect(images.placements.first.bounds).to eq Rect.new(1, 1, 8, 2)
    end

    it "asks for nothing when there is no picture" do
      images = store
      Fixtures.render Panel.new, 6, 2, images: images

      expect(images.placements).to be_empty
    end

    it "asks again every frame rather than leaving the last one up" do
      panel = Panel.new image: image
      images = store
      Fixtures.render panel, 6, 2, images: images
      Fixtures.render panel, 6, 2, images: images

      expect(images.placements.size).to eq 1
    end

    it "asks for nothing at all without a store" do
      expect(Fixtures.render(Panel.new(image: image), 6, 2)).to eq ["", ""]
    end
  end

  describe "#focused_border_style" do
    alias Border = TermBuf::Widgets::Border

    it "keeps the border it was given while the keyboard is elsewhere" do
      panel = Panel.new border: Border.plain(title: " box ")
      panel.focused_border_style = TermBuf::Style::DEFAULT.bold

      expect(panel.border.try &.style).to eq TermBuf::Style::DEFAULT
    end

    it "leaves the title alone when it lights the box" do
      lit = Border.plain(title: " box ").with_style TermBuf::Style::DEFAULT.bold

      expect(lit.title).to eq " box "
      expect(lit.style).to eq TermBuf::Style::DEFAULT.bold
    end

    it "changes no geometry, since a box is a cell per side either way" do
      panel = Panel.new border: Border.plain
      before = panel.inset
      panel.focused_border_style = TermBuf::Style::DEFAULT.bold

      expect(panel.inset).to eq before
    end
  end
end
