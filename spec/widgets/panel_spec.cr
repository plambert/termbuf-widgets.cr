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
end
