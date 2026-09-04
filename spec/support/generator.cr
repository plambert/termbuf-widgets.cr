module Fixtures
  # Builds random widget trees, so the layout invariants are checked against
  # shapes nobody thought to write down.
  class Generator
    alias Layout = TermBuf::Widgets::Layout
    alias Sizing = TermBuf::Widgets::Layout::Sizing
    alias Widget = TermBuf::Widgets::Widget

    # Pieces a random label is built from: narrow and wide clusters, a joined
    # emoji, runs of spaces and a newline, so wrapping has something to catch
    # on.
    ALPHABET = ["a", "bb", "ccc", "字", "字字", "🙂", "é", "the", "quick", " ", "  ", "\n"]

    def initialize(@random : Random)
    end

    # A tree at most *depth* deep with at most *fan_out* children anywhere.
    def tree(depth : Int32 = 4, fan_out : Int32 = 5) : Widget
      container 1, depth, fan_out
    end

    # A screen no larger than a small terminal and possibly a single cell.
    def screen : TermBuf::Rect
      TermBuf::Rect.full @random.rand(1..60), @random.rand(1..24)
    end

    private def container(level : Int32, depth : Int32, fan_out : Int32) : Widget
      box = Box.new
      shape box
      box.direction = pick Layout::Direction::Row, Layout::Direction::Column
      @random.rand(1..fan_out).times do
        node = box.add child(level, depth, fan_out)
        lift node, box if @random.rand(8).zero?
      end
      box
    end

    # Takes *widget* out of its parent's flow, anchored either to the screen or
    # to the parent it was lifted out of.
    private def lift(widget : Widget, parent : Widget) : Nil
      target = @random.rand(2).zero? ? nil : parent
      anchor = Layout::Anchor.new target, attach_point, attach_point,
        @random.rand(-3..3), @random.rand(-3..3)

      widget.floating = Layout::Floating.new anchor,
        z: @random.rand(0..4),
        capture: !@random.rand(4).zero?,
        overflow: pick(Layout::Overflow::Flip, Layout::Overflow::Clamp)
    end

    private def attach_point : Layout::AttachPoint
      points = Layout::AttachPoint.values
      points[@random.rand(points.size)]
    end

    private def child(level : Int32, depth : Int32, fan_out : Int32) : Widget
      return leaf if level >= depth || @random.rand(3).zero?

      container level + 1, depth, fan_out
    end

    private def leaf : Widget
      label = TermBuf::Widgets::Label.new text
      label.wrap = pick Layout::Wrap::Words, Layout::Wrap::Anywhere, Layout::Wrap::None
      shape label
      label
    end

    private def shape(widget : Widget) : Nil
      widget.width = sizing
      widget.height = sizing
      widget.padding = Layout::Padding.new @random.rand(0..2), @random.rand(0..2),
        @random.rand(0..2), @random.rand(0..2)
      widget.gap = @random.rand(0..2)
      widget.align_x = alignment
      widget.align_y = alignment
      widget.border = TermBuf::Border.plain if @random.rand(4).zero?
      widget.hidden = true if @random.rand(12).zero?
    end

    private def sizing : Sizing
      smallest = @random.rand(0..6)
      largest = @random.rand(3).zero? ? smallest + @random.rand(0..20) : Int32::MAX

      case @random.rand(4)
      when 0 then Sizing.fit smallest, largest
      when 1 then Sizing.grow @random.rand(1..3), smallest, largest
      when 2 then Sizing.fixed @random.rand(0..20)
      else        Sizing.new Sizing::Mode::Percent, smallest, largest, @random.rand(0..100)
      end
    end

    private def alignment : Layout::Align
      pick Layout::Align::Start, Layout::Align::Center, Layout::Align::End
    end

    private def text : String
      String.build do |io|
        @random.rand(0..6).times { io << ALPHABET[@random.rand(ALPHABET.size)] }
      end
    end

    private def pick(*choices : T) : T forall T
      choices[@random.rand(choices.size)]
    end
  end
end
