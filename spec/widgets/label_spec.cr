require "../spec_helper"

Spectator.describe TermBuf::Widgets::Label do
  alias Label = TermBuf::Widgets::Label
  alias Wrap = Layout::Wrap

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }

  describe "#intrinsic_width" do
    it "wants the unwrapped width and needs the widest word" do
      label = Label.new "aa bbbb"
      intrinsic = label.intrinsic_width policy

      expect(intrinsic.preferred).to eq 7
      expect(intrinsic.min).to eq 4
    end

    it "needs only the widest cluster when anything may break" do
      label = Label.new "aa bbbb", wrap: Wrap::Anywhere
      expect(label.intrinsic_width(policy).min).to eq 1
    end

    it "needs only the widest cluster when nothing wraps" do
      label = Label.new "aa bbbb", wrap: Wrap::None
      expect(label.intrinsic_width(policy).min).to eq 1
    end

    it "counts a wide cluster as the cells it takes" do
      label = Label.new "字字 a"
      intrinsic = label.intrinsic_width policy

      expect(intrinsic.preferred).to eq 6
      expect(intrinsic.min).to eq 4
    end

    it "wants the widest line of a text with newlines" do
      label = Label.new "ab\ncdef"
      expect(label.intrinsic_width(policy).preferred).to eq 4
    end
  end

  describe "#height_for_width" do
    it "counts the lines the words fall onto" do
      label = Label.new "aa bb cc dd"

      expect(label.height_for_width(11, policy)).to eq 1
      expect(label.height_for_width(5, policy)).to eq 2
      expect(label.height_for_width(2, policy)).to eq 4
    end

    it "counts the lines the clusters fall onto" do
      label = Label.new "abcdefg", wrap: Wrap::Anywhere
      expect(label.height_for_width(3, policy)).to eq 3
    end

    it "counts only the newlines when nothing wraps" do
      label = Label.new "ab\ncd", wrap: Wrap::None

      expect(label.height_for_width(1, policy)).to eq 2
      expect(label.height_for_width(80, policy)).to eq 2
    end
  end

  describe "the kept measurement" do
    it "hands back the same measurement for the same policy" do
      label = Label.new "aa bb"
      expect(label.measured(policy)).to be label.measured(policy)
    end

    it "measures again when the text changes" do
      label = Label.new "aa bb"
      label.measured policy
      label.text = "cc dd eeee"

      expect(label.intrinsic_width(policy).preferred).to eq 10
    end

    it "measures again under a different policy" do
      label = Label.new "字"
      narrow = TermBuf::Unicode::WidthPolicy.new ambiguous: 1
      expect(label.measured(narrow)).not_to be label.measured(policy.copy_with(ambiguous: 2))
    end

    it "wraps again when the mode changes" do
      label = Label.new "aaa bbb"
      expect(label.height_for_width(3, policy)).to eq 2

      label.wrap = Wrap::Anywhere
      expect(label.height_for_width(3, policy)).to eq 3
    end

    it "marks the tree dirty when the text changes" do
      label = Label.new "aa"
      tree = Layout::Tree.new label, Rect.full(10, 3)
      tree.layout_if_needed

      label.text = "bb"
      expect(tree.dirty?).to be_true
    end

    it "leaves the tree alone when the text is set to what it already was" do
      label = Label.new "aa"
      tree = Layout::Tree.new label, Rect.full(10, 3)
      tree.layout_if_needed

      label.text = "aa"
      expect(tree.dirty?).to be_false
    end
  end

  describe "in a layout" do
    it "moves its sibling down when it wraps onto a second row" do
      root = Fixtures::Box.new
      label = Label.new "aaa bbb"
      label.width = Sizing.grow
      sibling = Fixtures::Box.sized 3, 2
      root.add label, sibling

      tree = Layout::Tree.new root, Rect.full(20, 10)
      tree.layout

      expect(label.rect.height).to eq 1
      expect(sibling.rect.y).to eq 1

      tree.screen = Rect.full 5, 10
      tree.layout_if_needed

      expect(label.rect.width).to eq 5
      expect(label.rect.height).to eq 2
      expect(sibling.rect.y).to eq 2
    end

    it "sizes a fitting label to its own text" do
      root = Fixtures::Box.new
      label = Label.new "hello"
      root.add label

      Layout::Tree.new(root, Rect.full(20, 4)).layout
      expect(label.rect.width).to eq 5
      expect(label.rect.height).to eq 1
    end
  end

  describe "#draw" do
    it "writes each wrapped line on its own row" do
      label = Label.new "aa bb cc"
      Layout::Tree.new(label, Rect.full(5, 3)).layout

      expect(Fixtures.painted(label, 5, 3)).to eq ["aa bb", "cc", ""]
    end

    it "puts the leftover before the text when it is aligned right" do
      label = Label.new "ab", align: TermBuf::Unicode::Align::Right
      Layout::Tree.new(label, Rect.full(6, 1)).layout

      expect(Fixtures.painted(label, 6, 1)).to eq ["    ab"]
    end

    it "splits the leftover when it is centred" do
      label = Label.new "ab", align: TermBuf::Unicode::Align::Center
      Layout::Tree.new(label, Rect.full(6, 1)).layout

      expect(Fixtures.painted(label, 6, 1)).to eq ["  ab"]
    end

    it "marks a line it had to cut short" do
      label = Label.new "abcdefgh", wrap: Wrap::None, ellipsis: "…"
      label.width = Sizing.fixed 5
      Layout::Tree.new(label, Rect.full(5, 1)).layout

      expect(Fixtures.painted(label, 5, 1)).to eq ["abcd…"]
    end

    it "draws nothing at all for an empty text" do
      label = Label.new ""
      Layout::Tree.new(label, Rect.full(5, 2)).layout

      expect(Fixtures.painted(label, 5, 2)).to eq ["", ""]
    end
  end
end
