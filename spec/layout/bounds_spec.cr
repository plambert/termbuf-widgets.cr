require "../spec_helper"

# Percentage bounds, as the engine applies them. What `Sizing` stores and how
# it reads its own bounds are in sizing_spec.cr.
Spectator.describe "percentage bounds" do
  alias Box = Fixtures::Box
  alias Direction = Layout::Direction

  # A widget with the given direction and sizings, holding *children*.
  def holder(width : Sizing = Sizing.grow, height : Sizing = Sizing.grow,
             children : Enumerable(TermBuf::Widgets::Widget) = [] of TermBuf::Widgets::Widget,
             direction : Direction = Direction::Row) : Box
    box = Box.new
    box.direction = direction
    box.width = width
    box.height = height
    children.each { |child| box.add child }
    box
  end

  # A box that wants *width* columns, sized by *sizing*.
  def wide(width : Int32, sizing : Sizing) : Box
    box = Box.sized width
    box.width = sizing
    box
  end

  # A box that wants *lines* rows, sized by *sizing*.
  def tall(lines : Int32, sizing : Sizing) : Box
    box = Box.sized 1, lines
    box.height = sizing
    box
  end

  def lay(root : TermBuf::Widgets::Widget, columns : Int32, rows : Int32 = 10) : Nil
    Layout::Tree.new(root, Rect.full(columns, rows)).layout
  end

  describe "of the parent" do
    it "caps a fitting child at a share of the parent's width" do
      child = wide 30, Sizing.fit.with_max_percent(25)
      lay holder(children: [child]), 40

      expect(child.rect.width).to eq 10
    end

    it "caps a fitting child at a share of the parent's height" do
      child = tall 12, Sizing.fit.with_max_percent(25)
      lay holder(direction: Direction::Column, children: [child]), 40, 20

      expect(child.rect.height).to eq 5
    end

    # The difference from `Sizing.percent`, which would take 25% of the
    # twenty columns the fixed sibling left and come out at five.
    it "takes the whole content box, whatever the siblings take" do
      child = wide 30, Sizing.fit.with_max_percent(25)
      sibling = wide 20, Sizing.fixed(20)
      lay holder(children: [child, sibling]), 40

      expect(child.rect.width).to eq 10
    end

    it "takes the content box inside the parent's border and padding" do
      child = wide 30, Sizing.fit.with_max_percent(50)
      parent = holder children: [child]
      parent.padding = Layout::Padding.new 0, 3, 0, 3
      lay parent, 40

      expect(child.rect.width).to eq 17
    end

    it "bounds a child across the stacking axis as well as along it" do
      child = wide 30, Sizing.fit.with_max_percent(25)
      lay holder(direction: Direction::Column, children: [child]), 40

      expect(child.rect.width).to eq 10
    end

    it "raises a fitting child to a floor" do
      child = wide 3, Sizing.fit.with_min_percent(30)
      lay holder(children: [child]), 40

      expect(child.rect.width).to eq 12
    end
  end

  describe "of the component root" do
    def component(width : Sizing, height : Sizing, children : Enumerable(TermBuf::Widgets::Widget)) : Box
      box = holder width, height, children
      box.component_root = true
      box
    end

    it "caps a child at a share of the nearest component root's width" do
      child = wide 30, Sizing.fit.with_max_percent(50, of: :component)
      inner = holder children: [child]
      root = component Sizing.fixed(20), Sizing.grow, [inner]
      root.padding = Layout::Padding.new 0, 1, 0, 1
      lay holder(children: [root]), 80

      expect(child.rect.width).to eq 9
    end

    it "caps a child at a share of the nearest component root's height" do
      child = tall 30, Sizing.fit.with_max_percent(50, of: :component)
      inner = holder direction: Direction::Column, children: [child]
      root = component Sizing.grow, Sizing.fixed(12), [inner]
      lay holder(direction: Direction::Column, children: [root]), 40, 40

      expect(child.rect.height).to eq 6
    end

    it "takes the nearest of two component roots" do
      child = wide 30, Sizing.fit.with_max_percent(50, of: :component)
      inner = component Sizing.fixed(20), Sizing.grow, [child]
      outer = component Sizing.fixed(60), Sizing.grow, [inner]
      lay holder(children: [outer]), 80

      expect(child.rect.width).to eq 10
    end

    it "never takes a widget as its own component root" do
      inner = component Sizing.grow.with_max_percent(50, of: :component), Sizing.grow, [] of TermBuf::Widgets::Widget
      outer = component Sizing.fixed(60), Sizing.grow, [inner]
      lay holder(children: [outer]), 80

      expect(inner.rect.width).to eq 30
    end

    it "falls back to the screen when there is no component root" do
      child = wide 70, Sizing.fit.with_max_percent(50, of: :component)
      lay holder(children: [holder(children: [child])]), 80

      expect(child.rect.width).to eq 40
    end

    it "falls back to the screen on the vertical axis too" do
      child = tall 70, Sizing.fit.with_max_percent(25, of: :component)
      lay holder(direction: Direction::Column, children: [child]), 10, 40

      expect(child.rect.height).to eq 10
    end

    it "goes dirty when a widget becomes a component root" do
      root = holder
      tree = Layout::Tree.new root, Rect.full(10, 2)
      tree.layout

      root.component_root = false
      expect(tree.dirty?).to be_false

      root.component_root = true
      expect(tree.dirty?).to be_true
    end
  end

  describe "of the screen" do
    it "caps a child at a share of the screen's width" do
      child = wide 70, Sizing.fit.with_max_percent(25, of: :screen)
      lay holder(children: [holder(Sizing.fixed(60), children: [child])]), 80

      expect(child.rect.width).to eq 20
    end

    it "caps a child at a share of the screen's height" do
      child = tall 70, Sizing.fit.with_max_percent(25, of: :screen)
      lay holder(direction: Direction::Column, children: [child]), 10, 40

      expect(child.rect.height).to eq 10
    end

    # The screen is known before pass 1, so a fitting parent is measured from
    # the capped child and fits it.
    it "bounds a child before its fitting parent is measured" do
      child = wide 70, Sizing.fit.with_max_percent(25, of: :screen)
      parent = holder Sizing.fit, children: [child]
      lay holder(children: [parent]), 80

      expect(child.rect.width).to eq 20
      expect(parent.rect.width).to eq 20
    end

    it "does the same for a component bound with no component root" do
      child = wide 70, Sizing.fit.with_max_percent(25, of: :component)
      parent = holder Sizing.fit, children: [child]
      lay holder(children: [parent]), 80

      expect(parent.rect.width).to eq 20
    end
  end

  describe "with cells" do
    it "keeps a floor in cells under a percentage cap" do
      child = wide 3, Sizing.fit(min: 6).with_max_percent(25)
      lay holder(children: [child]), 40

      expect(child.rect.width).to eq 6
    end

    it "takes the smaller of two ceilings" do
      cells = wide 30, Sizing.fit(max: 8).with_max_percent(25)
      percent = wide 30, Sizing.fit(max: 12).with_max_percent(25)
      lay holder(direction: Direction::Column, children: [cells, percent]), 40

      expect(cells.rect.width).to eq 8
      expect(percent.rect.width).to eq 10
    end

    it "takes the larger of two floors" do
      cells = wide 3, Sizing.fit(min: 15).with_min_percent(25)
      percent = wide 3, Sizing.fit(min: 5).with_min_percent(25)
      lay holder(direction: Direction::Column, children: [cells, percent]), 40

      expect(cells.rect.width).to eq 15
      expect(percent.rect.width).to eq 10
    end

    it "lets a floor in percent win over a ceiling in cells" do
      child = wide 30, Sizing.fit(max: 5).with_min_percent(50)
      lay holder(children: [child]), 40

      expect(child.rect.width).to eq 20
    end

    it "lets a floor in cells win over a ceiling in percent" do
      child = wide 30, Sizing.fit(min: 15).with_max_percent(25)
      lay holder(children: [child]), 40

      expect(child.rect.width).to eq 15
    end

    it "takes each percentage of its own basis" do
      floor = wide 3, Sizing.fit.with_min_percent(25, of: :screen).with_max_percent(50)
      ceiling = wide 30, Sizing.fit.with_min_percent(25, of: :screen).with_max_percent(50)
      parent = holder Sizing.fixed(30), children: [floor, ceiling], direction: Direction::Column
      lay holder(children: [parent]), 40

      expect(floor.rect.width).to eq 10
      expect(ceiling.rect.width).to eq 15
    end
  end

  describe "in each mode" do
    it "caps a fixed size" do
      child = wide 0, Sizing.fixed(30).with_max_percent(25)
      lay holder(children: [child]), 40

      expect(child.rect.width).to eq 10
    end

    it "caps a grower and hands the rest to its sibling" do
      capped = wide 0, Sizing.grow.with_max_percent(25)
      free = wide 0, Sizing.grow
      lay holder(children: [capped, free]), 40

      expect([capped.rect.width, free.rect.width]).to eq [10, 30]
    end

    it "raises a grower to a floor" do
      held = wide 0, Sizing.grow.with_min_percent(75)
      free = wide 0, Sizing.grow
      lay holder(children: [held, free]), 40

      expect([held.rect.width, free.rect.width]).to eq [30, 10]
    end

    it "leaves a grower alone between its bounds" do
      held = wide 0, Sizing.grow.with_min_percent(30).with_max_percent(60)
      free = wide 0, Sizing.grow
      lay holder(children: [held, free]), 40

      expect([held.rect.width, free.rect.width]).to eq [20, 20]
    end

    it "caps a grower across the stacking axis" do
      child = wide 0, Sizing.grow.with_max_percent(25)
      lay holder(direction: Direction::Column, children: [child]), 40

      expect(child.rect.width).to eq 10
    end

    it "caps a percent along the stacking axis" do
      child = wide 0, Sizing.percent(50).with_max_percent(25)
      lay holder(children: [child]), 40

      expect(child.rect.width).to eq 10
    end

    it "caps a percent across the stacking axis" do
      child = wide 0, Sizing.percent(80).with_max_percent(50)
      lay holder(direction: Direction::Column, children: [child]), 40

      expect(child.rect.width).to eq 20
    end

    it "takes a percent's share of what is left, and its cap of the whole box" do
      child = wide 0, Sizing.percent(100).with_max_percent(25)
      sibling = wide 0, Sizing.fixed(20)
      lay holder(children: [child, sibling]), 40

      expect(child.rect.width).to eq 10
    end
  end

  # Pass 1 measures from the bottom up before any parent has a size, so a cap
  # of the parent or the component root can only cut the child down in pass
  # 2. A fitting parent has been measured from the uncapped child by then.
  describe "the pass 1 limit" do
    it "leaves a fitting parent as wide as its child's uncapped content" do
      child = wide 40, Sizing.fit.with_max_percent(25)
      parent = holder Sizing.fit, children: [child]
      lay holder(children: [parent]), 80

      expect(child.rect.width).to eq 10
      expect(parent.rect.width).to eq 40
    end

    it "does the same for a component cap" do
      child = wide 40, Sizing.fit.with_max_percent(25, of: :component)
      parent = holder Sizing.fit, children: [child]
      root = holder Sizing.fixed(40), children: [parent]
      root.component_root = true
      lay holder(children: [root]), 80

      expect(child.rect.width).to eq 10
      expect(parent.rect.width).to eq 40
    end

    it "fits a parent that grows, since it never measured the child" do
      child = wide 40, Sizing.fit.with_max_percent(25)
      parent = holder Sizing.grow, children: [child]
      lay holder(children: [parent]), 80

      expect(child.rect.width).to eq 20
      expect(parent.rect.width).to eq 80
    end
  end

  describe "a component root that fits" do
    it "is measured from its children uncapped, and caps them against that" do
      capped = wide 40, Sizing.fit.with_max_percent(25, of: :component)
      fixed = wide 0, Sizing.fixed(20)
      root = holder Sizing.fit, children: [capped, fixed]
      root.component_root = true
      lay holder(children: [root]), 80

      expect(root.rect.width).to eq 60
      expect(capped.rect.width).to eq 15
      expect(fixed.rect.width).to eq 20
    end

    it "lays out the same way every time" do
      capped = wide 40, Sizing.fit.with_max_percent(25, of: :component)
      root = holder Sizing.fit, children: [capped, wide(0, Sizing.fixed(20))]
      root.component_root = true
      tree = Layout::Tree.new holder(children: [root]), Rect.full(80, 10)

      widths = Array.new(3) do
        tree.layout
        {root.rect.width, capped.rect.width}
      end
      expect(widths.uniq).to eq [{60, 15}]
    end
  end

  describe "a float" do
    # A root holding a fixed target, and *float* hanging off *target* or the
    # screen.
    def floated(float : Box, on target : Box? = nil, columns : Int32 = 60) : Box
      root = holder
      root.add target if target
      float.floating = Layout::Floating.on target
      root.add float
      lay root, columns
      root
    end

    it "takes a parent cap of what it is anchored to" do
      target = wide 0, Sizing.fixed(20)
      float = wide 30, Sizing.fit.with_max_percent(50)
      floated float, on: target

      expect(float.rect.width).to eq 10
    end

    it "takes a parent cap of the screen when anchored to nothing" do
      float = wide 50, Sizing.fit.with_max_percent(50)
      floated float

      expect(float.rect.width).to eq 30
    end

    it "caps a growing float against its anchor" do
      target = wide 0, Sizing.fixed(20)
      float = wide 0, Sizing.grow.with_max_percent(50)
      floated float, on: target

      expect(float.rect.width).to eq 10
    end

    it "caps a percent float against its anchor" do
      target = wide 0, Sizing.fixed(20)
      float = wide 0, Sizing.percent(100).with_max_percent(25)
      floated float, on: target

      expect(float.rect.width).to eq 5
    end

    it "is a component root for the widgets in it" do
      child = wide 30, Sizing.fit.with_max_percent(50, of: :component)
      float = holder Sizing.fixed(40), Sizing.fixed(5), [child]
      float.padding = Layout::Padding.new 0, 1, 0, 1
      float.component_root = true
      floated float

      expect(child.rect.width).to eq 19
    end

    it "is a component root that fits" do
      child = wide 30, Sizing.fit.with_max_percent(25, of: :component)
      float = holder Sizing.fit, Sizing.fixed(5), [child, wide(0, Sizing.fixed(10))]
      float.component_root = true
      floated float

      expect(float.rect.width).to eq 40
      expect(child.rect.width).to eq 10
    end

    it "lets the widgets in it find a component root above it" do
      child = wide 30, Sizing.fit.with_max_percent(50, of: :component)
      float = holder Sizing.fit, Sizing.fixed(5), [child]
      float.floating = Layout::Floating.on nil
      root = holder Sizing.fixed(24), children: [float]
      root.component_root = true
      lay holder(children: [root]), 60

      expect(child.rect.width).to eq 12
    end

    it "takes its own component cap from a component root above it" do
      float = wide 50, Sizing.fit.with_max_percent(50, of: :component)
      float.floating = Layout::Floating.on nil
      root = holder Sizing.fixed(24), children: [float]
      root.component_root = true
      lay holder(children: [root]), 60

      expect(float.rect.width).to eq 12
    end

    it "takes a component cap of the screen with no component root above it" do
      float = wide 50, Sizing.fit.with_max_percent(25, of: :component)
      floated float

      expect(float.rect.width).to eq 15
    end
  end

  # The layout hf's detail pane wants: a tag list down the right, as narrow as
  # its tags allow and never wider than a quarter of the pane.
  describe "a tag column in an overlay" do
    alias Label = TermBuf::Widgets::Label
    alias Panel = TermBuf::Widgets::Panel
    alias Rows = TermBuf::Widgets::Rows
    alias VirtualList = TermBuf::Widgets::VirtualList
    alias Tag = {String, Int32?}

    class DetailPane < TermBuf::Widgets::Overlay
      def initialize
        super z: Z::DIALOG
        @floating = Layout::Floating.on nil, Layout::AttachPoint::Center, Layout::AttachPoint::Center,
          z: Z::DIALOG
        @hidden = false
      end
    end

    def tag_list(tags : Array(Tag)) : VirtualList(Tag)
      list = VirtualList.new Rows.of(tags), width: Sizing.fit
      list.on_measure = ->(tag : Tag) { "#{tag[0]}  #{tag[1]}" }
      list
    end

    # The pane, the grow column, the tag column and the list, laid out on an
    # 80 by 24 screen. The pane is 60 across with a border, so its content
    # box is 58 and a quarter of that rounds to 15.
    def detail(tags : Array(Tag)) : {DetailPane, Box, Panel, VirtualList(Tag), Layout::Tree}
      pane = DetailPane.new
      pane.width = Sizing.fixed 60
      pane.height = Sizing.fixed 12
      pane.border = TermBuf::Widgets::Border.plain
      pane.component_root = true

      body = wide 0, Sizing.grow

      list = tag_list tags
      column = Panel.new width: Sizing.fit(min: 6).with_max_percent(25, of: :component),
        height: Sizing.grow
      column.add Label.new("Tags")
      column.add list

      row = Panel.new Direction::Row, width: Sizing.grow, height: Sizing.grow
      row.add body, column
      pane.add row

      root = holder
      root.add pane
      tree = Layout::Tree.new root, Rect.full(80, 24)
      tree.layout
      {pane, body, column, list, tree}
    end

    it "fits the column to short tag names" do
      pane, body, column, list, _tree = detail([{"rust", 3}, {"crystal", 12}, {"go", nil}] of Tag)

      expect(pane.content.width).to eq 58
      expect(column.rect.width).to eq 11
      expect(list.rect.width).to eq 11
      expect(body.rect.width).to eq 47
    end

    it "keeps the column at its floor when the tags are narrower" do
      _pane, _body, column, _list, _tree = detail([{"a", nil}] of Tag)

      expect(column.rect.width).to eq 6
    end

    it "stops the column at a quarter of the pane for a long name" do
      _pane, body, column, list, _tree = detail([{"rust", 3}, {"a-tag-name-far-too-long-to-show", 1}] of Tag)

      expect(column.rect.width).to eq 15
      expect(list.rect.width).to eq 15
      expect(body.rect.width).to eq 43
    end

    it "widens the column when the list is given new rows" do
      _pane, _body, column, list, tree = detail([{"rust", 3}] of Tag)
      expect(column.rect.width).to eq 7

      list.rows = Rows.of([{"rust", 3}, {"crystal", 12}] of Tag)
      expect(tree.dirty?).to be_true
      tree.layout_if_needed

      expect(column.rect.width).to eq 11
    end
  end
end
