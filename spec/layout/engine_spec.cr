require "../spec_helper"

Spectator.describe Layout::Engine do
  alias Box = Fixtures::Box

  # A row of *children* laid out across *width* columns, and the widths they
  # ended up with.
  def row_widths(children : Array(Box), width : Int32, gap : Int32 = 0) : Array(Int32)
    root = Box.new
    root.direction = Layout::Direction::Row
    root.gap = gap
    children.each { |child| root.add child }

    Layout::Tree.new(root, Rect.full(width, 4)).layout
    children.map &.rect.width
  end

  def percent_row(percents : Array(Int32)) : Array(Box)
    percents.map do |percent|
      box = Box.new
      box.width = Sizing.percent percent
      box
    end
  end

  def grow_row(sizings : Array(Sizing)) : Array(Box)
    sizings.map do |sizing|
      box = Box.new
      box.width = sizing
      box
    end
  end

  describe "percent sizing" do
    # The task these specs were written from expected 3/3/4 here, which is what
    # largest-remainder rounding gives. The stated algorithm reads each share
    # off a rounded cumulative boundary instead, and that lands the odd column
    # in the middle: 33% ends at 3.3 -> 3, 66% ends at 6.6 -> 7. The boundary
    # form is what keeps the shares summing exactly and what the other two
    # cases below require, so it is the one implemented.
    it "splits 33/33/34 of ten columns at the rounded boundaries" do
      expect(row_widths(percent_row([33, 33, 34]), 10)).to eq [3, 4, 3]
    end

    it "splits 50/50 of seven columns four and three" do
      expect(row_widths(percent_row([50, 50]), 7)).to eq [4, 3]
    end

    it "splits four quarters of ten columns three, two, three, two" do
      expect(row_widths(percent_row([25, 25, 25, 25]), 10)).to eq [3, 2, 3, 2]
    end

    it "leaves the gaps out of the shares at every width" do
      (20..40).each do |width|
        widths = row_widths percent_row([30, 30, 40]), width, gap: 1
        expect(widths.sum + 2).to eq width
      end
    end

    it "takes its share of the content box, not of the widget" do
      root = Box.new
      root.direction = Layout::Direction::Row
      root.padding = Layout::Padding.all 2
      child = Box.new
      child.width = Sizing.percent 50
      root.add child

      Layout::Tree.new(root, Rect.full(20, 5)).layout
      expect(child.rect.width).to eq 8
      expect(child.rect.x).to eq 2
    end

    # The rule between two halves is the case the rule exists for: a percent
    # that ignored it would claim its cell as well and overflow by one.
    it "shares what a fixed sibling left rather than the whole box" do
      rule = Box.new
      rule.width = Sizing.fixed 1
      panes = percent_row [50, 50]

      expect(row_widths([panes[0], rule, panes[1]], 21)).to eq [10, 1, 10]
    end

    it "shares what a fitting sibling left as well" do
      children = [Box.sized(3)] + percent_row([25, 75])
      expect(row_widths(children, 11)).to eq [3, 2, 6]
    end
  end

  describe "grow sizing" do
    it "raises a grower to its minimum and divides the rest" do
      children = grow_row [Sizing.grow(min: 5), Sizing.grow(min: 1), Sizing.grow(min: 1)]
      expect(row_widths(children, 10)).to eq [5, 3, 2]
    end

    it "caps a grower at its maximum and hands the surplus on" do
      children = grow_row [Sizing.grow(max: 2), Sizing.grow, Sizing.grow]
      expect(row_widths(children, 10)).to eq [2, 4, 4]
    end

    it "divides by weight" do
      children = grow_row [Sizing.grow(1), Sizing.grow(3)]
      expect(row_widths(children, 12)).to eq [3, 9]
    end

    it "takes what the fixed and fit children left" do
      children = [Box.sized(3), Box.new, Box.sized(2)]
      children[1].width = Sizing.grow
      expect(row_widths(children, 10)).to eq [3, 5, 2]
    end
  end

  describe "shrinking" do
    it "takes the shortfall in proportion to what each child has" do
      children = [Box.flexible(2, 8), Box.flexible(2, 4)]
      expect(row_widths(children, 6)).to eq [4, 2]
    end

    it "stops at each child's minimum" do
      children = [Box.flexible(4, 8), Box.flexible(2, 4)]
      expect(row_widths(children, 6)).to eq [4, 2]
    end

    it "overflows rather than breaking a minimum" do
      children = [Box.flexible(5, 8), Box.flexible(4, 4)]
      expect(row_widths(children, 6)).to eq [5, 4]
    end

    it "leaves a fixed child alone" do
      fixed = Box.new
      fixed.width = Sizing.fixed 6
      children = [fixed, Box.flexible(1, 6)]
      expect(row_widths(children, 8)).to eq [6, 2]
    end
  end

  describe "fitting" do
    it "sizes a row to the sum of its children, its gaps and its inset" do
      root = Box.new
      root.direction = Layout::Direction::Row
      root.gap = 2
      root.padding = Layout::Padding.all 1
      root.add Box.sized(3), Box.sized(4)

      Layout::Tree.new(root, Rect.full(40, 4)).layout
      expect(root.min_width).to eq 3 + 4 + 2 + 2
    end

    it "sizes a column to the widest of its children" do
      root = Box.new
      root.add Box.sized(3), Box.sized(7), Box.sized(5)

      Layout::Tree.new(root, Rect.full(40, 4)).layout
      expect(root.min_width).to eq 7
    end

    it "counts a border as a cell on every side" do
      root = Box.new
      root.border = TermBuf::Widgets::Border.plain
      root.add Box.sized(4)

      Layout::Tree.new(root, Rect.full(40, 6)).layout
      expect(root.min_width).to eq 6
      expect(root.content).to eq Rect.new(1, 1, 38, 4)
    end
  end

  describe "hidden widgets" do
    it "takes no room and no gap beside it" do
      middle = Box.sized 4
      middle.hidden = true
      children = [Box.sized(3), middle, Box.sized(5)]
      root = Box.new
      root.direction = Layout::Direction::Row
      root.gap = 1
      children.each { |child| root.add child }

      Layout::Tree.new(root, Rect.full(40, 4)).layout
      expect(root.min_width).to eq 3 + 1 + 5
      expect(children[2].rect.x).to eq 4
      expect(middle.rect.width).to eq 0
    end
  end

  describe "positioning" do
    it "lays a row out from the content origin with the gap between" do
      root = Box.new
      root.direction = Layout::Direction::Row
      root.gap = 2
      root.padding = Layout::Padding.all 1
      first = Box.sized 3
      second = Box.sized 4
      root.add first, second

      Layout::Tree.new(root, Rect.full(40, 5)).layout
      expect(first.rect.x).to eq 1
      expect(second.rect.x).to eq 6
    end

    it "puts the leftover before the children when they are aligned to the end" do
      root = Box.new
      root.direction = Layout::Direction::Row
      root.align_x = Layout::Align::End
      first = Box.sized 3
      root.add first

      Layout::Tree.new(root, Rect.full(10, 5)).layout
      expect(first.rect.x).to eq 7
    end

    it "splits the leftover when they are centred" do
      root = Box.new
      root.direction = Layout::Direction::Row
      root.align_x = Layout::Align::Center
      first = Box.sized 3
      root.add first

      Layout::Tree.new(root, Rect.full(10, 5)).layout
      expect(first.rect.x).to eq 3
    end

    it "leaves the alignment alone when a grower already took the leftover" do
      root = Box.new
      root.direction = Layout::Direction::Row
      root.align_x = Layout::Align::End
      first = Box.sized 3
      second = Box.new
      second.width = Sizing.grow
      root.add first, second

      Layout::Tree.new(root, Rect.full(10, 5)).layout
      expect(first.rect.x).to eq 0
      expect(second.rect.width).to eq 7
    end

    it "aligns each child across the stacking axis on its own" do
      root = Box.new
      root.direction = Layout::Direction::Row
      root.align_y = Layout::Align::Center
      first = Box.sized 3, 2
      root.add first

      Layout::Tree.new(root, Rect.full(10, 6)).layout
      expect(first.rect.height).to eq 2
      expect(first.rect.y).to eq 2
    end
  end

  describe "clipping" do
    def scroll_panel(scroll : Int32) : {Box, Array(Box)}
      root = Box.new
      root.clip_y = true
      root.scroll_y = scroll
      children = [Box.sized(4, 4), Box.sized(4, 4), Box.sized(4, 4)]
      children.each { |child| root.add child }
      Layout::Tree.new(root, Rect.full(10, 6)).layout
      {root, children}
    end

    it "compresses the children when it does not clip" do
      root = Box.new
      children = [Box.sized(4, 4), Box.sized(4, 4), Box.sized(4, 4)]
      children.each { |child| root.add child }
      Layout::Tree.new(root, Rect.full(10, 6)).layout

      expect(children.map(&.rect.height)).to eq [2, 2, 2]
    end

    it "leaves the children uncompressed when it clips" do
      _, children = scroll_panel 0
      expect(children.map(&.rect.height)).to eq [4, 4, 4]
      expect(children.map(&.rect.y)).to eq [0, 4, 8]
    end

    it "shifts the children by its scroll" do
      _, children = scroll_panel 2
      expect(children.map(&.rect.height)).to eq [4, 4, 4]
      expect(children.map(&.rect.y)).to eq [-2, 2, 6]
    end
  end

  describe "off-axis sizing" do
    it "grows a child to the content box and no further" do
      root = Box.new
      child = Box.sized 3
      child.width = Sizing.grow max: 6
      root.add child

      Layout::Tree.new(root, Rect.full(10, 4)).layout
      expect(child.rect.width).to eq 6
    end

    it "clamps a fixed child that is wider than the content box" do
      root = Box.new
      child = Box.new
      child.width = Sizing.fixed 20
      root.add child

      Layout::Tree.new(root, Rect.full(10, 4)).layout
      expect(child.rect.width).to eq 10
    end

    it "lets a fixed child overflow along the stacking axis" do
      root = Box.new
      root.direction = Layout::Direction::Row
      child = Box.new
      child.width = Sizing.fixed 20
      root.add child

      Layout::Tree.new(root, Rect.full(10, 4)).layout
      expect(child.rect.width).to eq 20
    end
  end

  describe "invalidation" do
    it "lays out again only when something changed" do
      root = Box.new
      root.add Box.sized(3)
      tree = Layout::Tree.new root, Rect.full(10, 4)

      expect(tree.dirty?).to be_true
      tree.layout_if_needed
      expect(tree.dirty?).to be_false

      root.gap = 2
      expect(tree.dirty?).to be_true
    end

    it "stays clean when a setter is given the value it already has" do
      root = Box.new
      tree = Layout::Tree.new root, Rect.full(10, 4)
      tree.layout_if_needed

      root.gap = 0
      root.direction = Layout::Direction::Column
      expect(tree.dirty?).to be_false
    end

    it "goes dirty on a new screen" do
      tree = Layout::Tree.new Box.new, Rect.full(10, 4)
      tree.layout_if_needed

      tree.screen = Rect.full 12, 4
      expect(tree.dirty?).to be_true
    end

    context "with verification on" do
      before_each { Layout::Tree.verify_invalidation = true }
      after_each { Layout::Tree.verify_invalidation = false }

      it "passes a tree nothing has touched" do
        root = Box.new
        root.direction = Layout::Direction::Row
        root.add Box.sized(3), Box.sized(4)
        tree = Layout::Tree.new root, Rect.full(20, 4)
        tree.layout_if_needed

        expect { tree.layout_if_needed }.not_to raise_error
      end

      it "catches geometry changed behind the setters' backs" do
        root = Box.new
        root.direction = Layout::Direction::Row
        root.add Box.sized(3), Box.sized(4)
        tree = Layout::Tree.new root, Rect.full(20, 4)
        tree.layout_if_needed

        root.poke_gap 2
        expect { tree.layout_if_needed }.to raise_error(Layout::MissedInvalidation, /Box/)
      end
    end
  end

  describe "the tree" do
    it "refuses a widget that already has a parent" do
      root = Box.new
      child = Box.new
      root.add child

      expect { Box.new.add child }.to raise_error(Layout::Error, /already has a parent/)
    end

    it "forgets a child that is removed" do
      root = Box.new
      child = Box.new
      root.add child

      expect(root.remove(child)).to be child
      expect(root.children).to be_empty
      expect(child.parent).to be_nil
    end
  end
end
