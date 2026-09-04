require "../spec_helper"

Spectator.describe TermBuf::Widgets::Divider do
  alias Divider = TermBuf::Widgets::Divider
  alias Panel = TermBuf::Widgets::Panel
  alias Label = TermBuf::Widgets::Label

  describe "which way it runs" do
    it "runs across in a column, which is what separates its rows" do
      root = Panel.new width: Sizing.grow
      root.add Label.new("a"), Divider.new, Label.new("b")

      expect(Fixtures.render(root, 5, 3)).to eq ["a", "─────", "b"]
    end

    it "runs down in a row, which is what separates its columns" do
      root = Panel.new height: Sizing.grow
      root.direction = Layout::Direction::Row
      root.add Label.new("a"), Divider.new, Label.new("b")

      expect(Fixtures.render(root, 3, 3)).to eq ["a│b", " │", " │"]
    end

    it "takes what it was told over what its parent stacks" do
      root = Panel.new height: Sizing.grow
      rule = Divider.new orientation: Divider::Orientation::Vertical
      root.add rule

      expect(Fixtures.render(root, 4, 2)).to eq ["│", "│"]
    end

    it "runs across when it has no parent at all" do
      expect(Divider.new.horizontal?).to be_true
    end

    it "changes when its parent does" do
      root = Panel.new width: Sizing.grow, height: Sizing.grow
      rule = Divider.new
      root.add rule
      tree = Layout::Tree.new root, Rect.full(4, 3)
      tree.layout

      expect(rule.rect).to eq Rect.new(0, 0, 4, 1)

      root.direction = Layout::Direction::Row
      tree.layout_if_needed

      expect(rule.rect).to eq Rect.new(0, 0, 1, 3)
    end
  end

  describe "its size" do
    it "is one cell thick and as long as there is room" do
      root = Panel.new width: Sizing.grow
      rule = Divider.new
      root.add rule

      Layout::Tree.new(root, Rect.full(9, 4)).layout
      expect(rule.rect).to eq Rect.new(0, 0, 9, 1)
    end

    it "needs a cell even where there is nothing to give it" do
      root = Panel.new
      rule = Divider.new
      root.add rule

      Layout::Tree.new(root, Rect.full(9, 4)).layout
      expect(rule.min_width).to eq 1
    end
  end

  describe "a label" do
    it "sits in the middle of the rule" do
      root = Panel.new width: Sizing.grow
      root.add Divider.new(label: "ab")

      expect(Fixtures.render(root, 10, 1)).to eq ["─── ab ───"]
    end

    it "keeps a space either side of itself" do
      root = Panel.new width: Sizing.grow
      root.add Divider.new(label: "x")

      expect(Fixtures.render(root, 7, 1)).to eq ["── x ──"]
    end

    it "makes the rule wide enough to hold it" do
      root = Panel.new
      rule = Divider.new label: "details"
      root.add rule

      Layout::Tree.new(root, Rect.full(40, 3)).layout
      expect(rule.min_width).to eq 9
    end

    it "is cut rather than overflowing a rule too short for it" do
      root = Panel.new width: Sizing.grow
      root.add Divider.new(label: "a long label")

      expect(Fixtures.render(root, 5, 1).first.size).to be <= 5
    end

    it "is ignored on a rule that runs down" do
      root = Panel.new height: Sizing.grow
      root.add Divider.new(orientation: Divider::Orientation::Vertical, label: "x")

      expect(Fixtures.render(root, 4, 2)).to eq ["│", "│"]
    end
  end

  describe "how it is drawn" do
    it "takes the glyph it was given" do
      root = Panel.new width: Sizing.grow
      root.add Divider.new(glyph: '=')

      expect(Fixtures.render(root, 6, 1)).to eq ["======"]
    end

    it "takes a style like anything else" do
      root = Panel.new width: Sizing.grow
      rule = Divider.new
      rule.style = TermBuf::Style::DEFAULT.faint
      root.add rule

      buffer = Fixtures.painted root, 4, 1
      expect(Fixtures.style_at(buffer, 0, 0).attributes.faint?).to be_true
    end
  end
end
