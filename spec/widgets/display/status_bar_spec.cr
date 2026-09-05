require "../../spec_helper"

Spectator.describe TermBuf::Widgets::StatusBar do
  alias StatusBar = TermBuf::Widgets::StatusBar
  alias Style = TermBuf::Style

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }

  # A bar with two pairs, which is "a: 1 | b: 22" laid end to end.
  def two_pairs : StatusBar
    bar = StatusBar.new
    bar.add "a", 1
    bar.add "b", 22
    bar
  end

  describe "#add" do
    it "keeps the pairs in the order they were added" do
      bar = two_pairs
      expect(bar.items.map(&.label)).to eq ["a", "b"]
    end

    it "turns a value into text with to_s" do
      bar = StatusBar.new
      bar.add "count", 42

      expect(bar.items.first.text).to eq "42"
    end

    it "turns a value into text with the block it was given" do
      bar = StatusBar.new
      rate = ->(count : Int32) { "#{count}/s" }
      bar.add "throughput", 90, &rate

      expect(bar.items.first.text).to eq "90/s"
    end

    it "marks the tree dirty" do
      bar = StatusBar.new
      tree = Layout::Tree.new bar, Rect.full(20, 3)
      tree.layout_if_needed

      bar.add "a", 1
      expect(tree.dirty?).to be_true
    end
  end

  describe "#set" do
    it "replaces the text of a pair already there" do
      bar = two_pairs
      bar.set "a", 7

      expect(bar["a"]?.try &.text).to eq "7"
      expect(bar.items.size).to eq 2
    end

    it "adds a pair there was none of" do
      bar = StatusBar.new
      bar.set "fresh", "yes"

      expect(bar.items.map(&.label)).to eq ["fresh"]
    end

    it "formats through the block it was given" do
      bar = StatusBar.new
      bar.add "load", 0.5
      bar.set("load", 0.75) { |amount| "%.2f" % amount }

      expect(bar["load"]?.try &.text).to eq "0.75"
    end

    it "marks the tree dirty when the pair changed width" do
      bar = two_pairs
      tree = Layout::Tree.new bar, Rect.full(20, 3)
      tree.layout_if_needed

      bar.set "a", 100
      expect(tree.dirty?).to be_true
    end

    it "leaves the tree alone when the pair is the same width" do
      bar = two_pairs
      tree = Layout::Tree.new bar, Rect.full(20, 3)
      tree.layout_if_needed

      bar.set "a", 9
      expect(tree.dirty?).to be_false
    end
  end

  describe "#remove" do
    it "takes the pair out and hands it back" do
      bar = two_pairs
      taken = bar.remove "a"

      expect(taken.try &.label).to eq "a"
      expect(bar.items.map(&.label)).to eq ["b"]
    end

    it "answers nil for a pair that was not there" do
      expect(two_pairs.remove("nowhere")).to be_nil
    end
  end

  describe "#intrinsic_width" do
    it "wants every pair and the separators between them" do
      bar = two_pairs
      expect(bar.intrinsic_width(policy).preferred).to eq 12
    end

    it "needs no more than its first label" do
      bar = two_pairs
      expect(bar.intrinsic_width(policy).min).to eq 1
    end

    it "wants nothing at all with no pairs" do
      intrinsic = StatusBar.new.intrinsic_width policy

      expect(intrinsic.preferred).to eq 0
      expect(intrinsic.min).to eq 0
    end
  end

  describe "#height_for_width" do
    it "is one row however wide it is" do
      bar = two_pairs

      expect(bar.height_for_width(4, policy)).to eq 1
      expect(bar.height_for_width(80, policy)).to eq 1
    end
  end

  describe "#draw" do
    it "lays the pairs out on one row" do
      expect(Fixtures.render(two_pairs, 20, 2)).to eq ["a: 1 | b: 22", ""]
    end

    it "cuts the pairs that do not fit and marks the cut" do
      expect(Fixtures.render(two_pairs, 9, 1)).to eq ["a: 1 | b…"]
    end

    it "cuts without a mark when there is no ellipsis" do
      bar = two_pairs
      bar.ellipsis = nil

      expect(Fixtures.render(bar, 9, 1)).to eq ["a: 1 | b:"]
    end

    it "cuts inside the first pair when even that does not fit" do
      expect(Fixtures.render(two_pairs, 3, 1)).to eq ["a:…"]
    end

    it "uses the separators it was given" do
      bar = StatusBar.new separator: "  ", label_separator: "="
      bar.add "a", 1
      bar.add "b", 2

      expect(Fixtures.render(bar, 20, 1)).to eq ["a=1  b=2"]
    end

    it "draws nothing at all with no pairs" do
      expect(Fixtures.render(StatusBar.new, 8, 1)).to eq [""]
    end

    it "draws a label faint and a value in its own style" do
      bar = StatusBar.new
      bar.add "a", 1, Style::DEFAULT.bold
      painted = Fixtures.painted bar, 20, 1

      expect(Fixtures.style_at(painted, 0, 0).has?(TermBuf::Attributes::Faint)).to be_true
      expect(Fixtures.style_at(painted, 3, 0).has?(TermBuf::Attributes::Bold)).to be_true
    end
  end

  describe "in a layout" do
    it "grows to the width it is given and stays one row" do
      root = TermBuf::Widgets::Panel.new width: Sizing.grow, height: Sizing.grow
      bar = two_pairs
      root.add bar

      Layout::Tree.new(root, Rect.full(24, 5)).layout

      expect(bar.rect.width).to eq 24
      expect(bar.rect.height).to eq 1
    end
  end
end
