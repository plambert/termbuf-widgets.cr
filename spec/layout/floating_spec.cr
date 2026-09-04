require "../spec_helper"

Spectator.describe Layout::Floating do
  alias Box = Fixtures::Box
  alias Point = Layout::AttachPoint
  alias Overflow = Layout::Overflow

  # The nine attach points are declared left to right, top to bottom, so the
  # column and row a point names fall out of its value. Worked out here from
  # the declaration rather than from the implementation, which is the thing
  # under test.
  def offset_of(point : Point, width : Int32, height : Int32) : {Int32, Int32}
    across = case point.value % 3
             when 0 then 0
             when 1 then width // 2
             else        width
             end
    down = case point.value // 3
           when 0 then 0
           when 1 then height // 2
           else        height
           end

    {across, down}
  end

  # A root whose only flow child is a fixed target of *target_width* by
  # *target_height*, with a float of *width* by *height* hanging off it.
  def anchored(element : Point, parent : Point, screen : Rect,
               target_width : Int32 = 20, target_height : Int32 = 10,
               width : Int32 = 4, height : Int32 = 2,
               padding : Layout::Padding = Layout::Padding.new(5, 0, 0, 6),
               overflow : Overflow = Overflow::Clamp,
               dx : Int32 = 0, dy : Int32 = 0) : {Box, Box}
    root = Box.new
    root.padding = padding

    target = Box.new
    target.width = Sizing.fixed target_width
    target.height = Sizing.fixed target_height
    root.add target

    float = Box.new
    float.width = Sizing.fixed width
    float.height = Sizing.fixed height
    float.floating = Layout::Floating.on target, element, parent,
      dx: dx, dy: dy, overflow: overflow
    root.add float

    Layout::Tree.new(root, screen).layout
    {target, float}
  end

  describe "the attach matrix" do
    it "lays the float's point on the target's, for all eighty-one pairs" do
      screen = Rect.full 40, 20

      Point.values.each do |element|
        Point.values.each do |parent|
          target, float = anchored element, parent, screen

          from_float = offset_of element, float.rect.width, float.rect.height
          from_target = offset_of parent, target.rect.width, target.rect.height
          expected_x = target.rect.x + from_target[0] - from_float[0]
          expected_y = target.rect.y + from_target[1] - from_float[1]

          expect({float.rect.x, float.rect.y}).to eq({expected_x, expected_y})
        end
      end
    end

    it "hangs the float off a target that is not at the origin" do
      target, float = anchored Point::LeftTop, Point::LeftBottom, Rect.full(40, 20)

      expect(target.rect).to eq Rect.new(6, 5, 20, 10)
      expect(float.rect).to eq Rect.new(6, 15, 4, 2)
    end

    it "shifts the result by the anchor's offsets" do
      _, float = anchored Point::LeftTop, Point::LeftTop, Rect.full(40, 20), dx: 2, dy: 1
      expect(float.rect).to eq Rect.new(8, 6, 4, 2)
    end
  end

  describe "overflow" do
    it "opens the other way at the right edge" do
      _, float = anchored Point::LeftTop, Point::RightTop, Rect.full(20, 10),
        target_width: 4, target_height: 2, width: 6, height: 2,
        padding: Layout::Padding.new(0, 0, 0, 16), overflow: Overflow::Flip

      # Attached at the target's right edge the float would run to column 26 on
      # a screen twenty wide, so it mirrors and opens leftward instead.
      expect(float.rect.x).to eq 10
    end

    it "opens upward at the bottom edge" do
      _, float = anchored Point::LeftTop, Point::LeftBottom, Rect.full(20, 10),
        target_width: 4, target_height: 2, width: 4, height: 5,
        padding: Layout::Padding.new(8, 0, 0, 0), overflow: Overflow::Flip

      expect(float.rect.y).to eq 3
    end

    it "keeps its side and slides back when it is told to clamp" do
      _, float = anchored Point::LeftTop, Point::LeftBottom, Rect.full(20, 10),
        target_width: 4, target_height: 2, width: 4, height: 5,
        padding: Layout::Padding.new(8, 0, 0, 0), overflow: Overflow::Clamp

      expect(float.rect.y).to eq 5
    end

    it "slides back when mirroring would not fit either" do
      _, float = anchored Point::LeftTop, Point::RightTop, Rect.full(20, 10),
        target_width: 18, target_height: 2, width: 8, height: 2,
        padding: Layout::Padding.new(0, 0, 0, 1), overflow: Overflow::Flip

      expect(float.rect.x).to eq 12
    end

    it "sits at the left edge when it is wider than the screen" do
      _, float = anchored Point::LeftTop, Point::RightTop, Rect.full(12, 6),
        target_width: 4, target_height: 2, width: 30, height: 2,
        padding: Layout::Padding.new(0, 0, 0, 2), overflow: Overflow::Flip

      expect(float.rect.x).to eq 0
      expect(float.rect.width).to eq 30
    end

    it "sits at the top when it is taller than the screen" do
      _, float = anchored Point::LeftTop, Point::LeftBottom, Rect.full(12, 6),
        target_width: 4, target_height: 2, width: 4, height: 20,
        padding: Layout::Padding.new(1, 0, 0, 0), overflow: Overflow::Clamp

      expect(float.rect.y).to eq 0
    end
  end

  describe "the anchor target" do
    it "falls back to the screen when the target is hidden" do
      root = Box.new
      target = Box.new
      target.width = Sizing.fixed 10
      target.height = Sizing.fixed 4
      root.add target

      float = Box.new
      float.width = Sizing.fixed 3
      float.height = Sizing.fixed 2
      float.floating = Layout::Floating.on target, Point::RightBottom, Point::RightBottom
      root.add float

      tree = Layout::Tree.new root, Rect.full(20, 8)
      tree.layout
      expect(float.rect).to eq Rect.new(7, 2, 3, 2)

      target.hidden = true
      tree.layout
      expect(float.rect).to eq Rect.new(17, 6, 3, 2)
    end

    it "falls back to the screen when the target has been taken out" do
      root = Box.new
      target = Box.new
      target.width = Sizing.fixed 10
      target.height = Sizing.fixed 4
      root.add target

      float = Box.new
      float.width = Sizing.fixed 3
      float.height = Sizing.fixed 2
      float.floating = Layout::Floating.on target, Point::RightBottom, Point::RightBottom
      root.add float

      tree = Layout::Tree.new root, Rect.full(20, 8)
      tree.layout
      root.remove target
      tree.layout

      expect(float.rect).to eq Rect.new(17, 6, 3, 2)
    end

    it "measures itself against the screen when there is no target" do
      root = Box.new
      float = Box.new
      float.width = Sizing.percent 50
      float.height = Sizing.grow
      float.floating = Layout::Floating.new
      root.add float

      Layout::Tree.new(root, Rect.full(20, 8)).layout
      expect(float.rect).to eq Rect.new(0, 0, 10, 8)
    end
  end

  describe "the flow it was lifted out of" do
    it "takes no room from its parent and no gap beside it" do
      root = Box.new
      root.direction = Layout::Direction::Row
      root.gap = 1
      first = Box.sized 3
      float = Box.sized 5
      float.floating = Layout::Floating.new
      second = Box.sized 4
      root.add first, float, second

      Layout::Tree.new(root, Rect.full(30, 4)).layout
      expect(root.min_width).to eq 3 + 1 + 4
      expect(second.rect.x).to eq 4
    end
  end

  describe "nesting" do
    it "lays a float inside a float out after the one that hosts it" do
      root = Box.new
      outer = Box.new
      outer.width = Sizing.fixed 10
      outer.height = Sizing.fixed 4
      outer.floating = Layout::Floating.new Layout::Anchor.new(nil, Point::LeftTop, Point::Center)
      root.add outer

      host = Box.sized 2, 1
      outer.add host

      inner = Box.new
      inner.width = Sizing.fixed 3
      inner.height = Sizing.fixed 1
      inner.floating = Layout::Floating.on host, Point::LeftTop, Point::LeftBottom
      outer.add inner

      tree = Layout::Tree.new root, Rect.full(20, 10)
      tree.layout

      expect(tree.floats).to eq [outer, inner]
      expect(outer.rect).to eq Rect.new(10, 5, 10, 4)
      expect(inner.rect).to eq Rect.new(10, 6, 3, 1)
    end
  end

  describe "painting order" do
    it "puts the root first and the floats by their z, lowest first" do
      root = Box.new
      above = Box.sized 2
      above.floating = Layout::Floating.new z: 5
      below = Box.sized 2
      below.floating = Layout::Floating.new z: 1
      root.add above, below

      tree = Layout::Tree.new root, Rect.full(10, 4)
      tree.layout

      expect(tree.roots_in_z_order).to eq [root, below, above]
    end

    it "keeps declaration order between floats at the same z" do
      root = Box.new
      first = Box.sized 2
      first.floating = Layout::Floating.new z: 3
      second = Box.sized 2
      second.floating = Layout::Floating.new z: 3
      third = Box.sized 2
      third.floating = Layout::Floating.new z: 3
      root.add first, second, third

      tree = Layout::Tree.new root, Rect.full(10, 4)
      tree.layout

      expect(tree.roots_in_z_order).to eq [root, first, second, third]
    end
  end

  describe "#hit" do
    def covered : {Layout::Tree, Box, Box}
      root = Box.new
      under = Box.new
      under.width = Sizing.fixed 10
      under.height = Sizing.fixed 4
      root.add under

      over = Box.new
      over.width = Sizing.fixed 6
      over.height = Sizing.fixed 2
      root.add over

      tree = Layout::Tree.new root, Rect.full(20, 8)
      {tree, under, over}
    end

    it "gives the float the point when it captures" do
      tree, _, over = covered
      over.floating = Layout::Floating.new
      tree.layout

      expect(tree.hit(2, 1)).to be over
    end

    it "passes the point through a float that does not capture" do
      tree, under, over = covered
      over.floating = Layout::Floating.new capture: false
      tree.layout

      expect(tree.hit(2, 1)).to be under
    end

    it "reaches the deepest widget under the point" do
      root = Box.new
      root.padding = Layout::Padding.all 1
      inner = Box.new
      inner.width = Sizing.fixed 4
      inner.height = Sizing.fixed 2
      root.add inner

      tree = Layout::Tree.new root, Rect.full(10, 6)
      tree.layout

      expect(tree.hit(2, 2)).to be inner
      expect(tree.hit(8, 5)).to be root
    end

    it "answers nothing outside the screen" do
      tree, _, _ = covered
      tree.layout

      expect(tree.hit(-1, 0)).to be_nil
      expect(tree.hit(0, 40)).to be_nil
    end

    it "skips a hidden widget" do
      root = Box.new
      inner = Box.new
      inner.width = Sizing.fixed 4
      inner.height = Sizing.fixed 2
      inner.hidden = true
      root.add inner

      tree = Layout::Tree.new root, Rect.full(10, 6)
      tree.layout

      expect(tree.hit(1, 1)).to be root
    end
  end
end
