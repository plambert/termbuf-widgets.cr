require "../../spec_helper"

Spectator.describe TermBuf::Widgets::SingleValue do
  alias SingleValue = TermBuf::Widgets::SingleValue
  alias Style = TermBuf::Style
  alias Color = TermBuf::Color

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }
  let(green) { Style::DEFAULT.fg Color.rgb(0, 255, 0) }
  let(amber) { Style::DEFAULT.fg Color.rgb(255, 191, 0) }
  let(red) { Style::DEFAULT.fg Color.rgb(255, 0, 0) }

  # A tile showing a whole number, which is what most of these are about.
  def whole(value : Number, caption : String? = nil) : SingleValue
    tile = SingleValue.new value, caption: caption
    tile.format = ->(amount : Float64) { amount.to_i.to_s }
    tile
  end

  describe "#text" do
    it "says what the formatter says" do
      tile = SingleValue.new 94.25
      tile.format = ->(amount : Float64) { "%.1f%%" % amount }

      expect(tile.text).to eq "94.2%"
    end

    it "falls back to the number's own to_s" do
      expect(SingleValue.new(3.5).text).to eq "3.5"
    end
  end

  describe "#style_of_value" do
    it "takes the style of the highest bound at or below the value" do
      tile = whole 75
      tile.thresholds = [{0.0, green}, {70.0, amber}, {90.0, red}]

      expect(tile.style_of_value).to eq amber
    end

    it "takes the top style once the value is past the last bound" do
      tile = whole 96
      tile.thresholds = [{0.0, green}, {70.0, amber}, {90.0, red}]

      expect(tile.style_of_value).to eq red
    end

    it "keeps its own style for a value under every bound" do
      tile = whole 10
      tile.thresholds = [{50.0, amber}]

      expect(tile.style_of_value).to eq tile.value_style
    end

    it "asks the block instead when it has one" do
      tile = whole 10
      tile.thresholds = [{0.0, amber}]
      tile.colour = ->(amount : Float64) { amount < 50 ? green : red }

      expect(tile.style_of_value).to eq green
    end
  end

  describe "#intrinsic_width" do
    it "wants the wider of the value and the caption" do
      expect(whole(42, "requests").intrinsic_width(policy).preferred).to eq 8
    end

    it "wants the value when there is no caption" do
      expect(whole(1234).intrinsic_width(policy).preferred).to eq 4
    end

    it "survives in a single cell" do
      expect(whole(1234, "requests").intrinsic_width(policy).min).to eq 1
    end
  end

  describe "#height_for_width" do
    it "is two rows with a caption and one without" do
      expect(whole(1, "n").height_for_width(20, policy)).to eq 2
      expect(whole(1).height_for_width(20, policy)).to eq 1
    end
  end

  describe "#draw" do
    it "puts the caption under the value" do
      expect(Fixtures.render(whole(42, "hits"), 10, 3)).to eq ["42", "hits", ""]
    end

    it "aligns both rows to the right" do
      tile = whole 42, "hits"
      tile.align = TermBuf::Unicode::Align::Right

      expect(Fixtures.render(tile, 6, 2)).to eq ["    42", "  hits"]
    end

    it "centres both rows" do
      tile = whole 42, "hits"
      tile.align = TermBuf::Unicode::Align::Center

      expect(Fixtures.render(tile, 8, 2)).to eq ["   42", "  hits"]
    end

    it "marks a caption it had to cut" do
      expect(Fixtures.render(whole(42, "requests"), 5, 2)).to eq ["42", "requ…"]
    end

    it "cuts without a mark when there is no ellipsis" do
      tile = whole 42, "requests"
      tile.ellipsis = nil

      expect(Fixtures.render(tile, 5, 2)).to eq ["42", "reque"]
    end

    it "draws the value in the style its threshold gave it" do
      tile = whole 95, "cpu"
      tile.thresholds = [{0.0, green}, {90.0, red}]
      painted = Fixtures.painted tile, 10, 2

      expect(Fixtures.style_at(painted, 0, 0).foreground).to eq Color.rgb(255, 0, 0)
    end

    it "leaves the caption row out of a box only one row tall" do
      expect(Fixtures.render(whole(42, "hits"), 10, 1)).to eq ["42"]
    end
  end

  describe "in a layout" do
    it "fits the content it was given" do
      root = TermBuf::Widgets::Panel.new width: Sizing.grow, height: Sizing.grow
      tile = whole 1234, "requests"
      root.add tile

      Layout::Tree.new(root, Rect.full(30, 6)).layout

      expect(tile.rect.width).to eq 8
      expect(tile.rect.height).to eq 2
    end

    it "marks the tree dirty when the value changes" do
      tile = whole 1, "n"
      tree = Layout::Tree.new tile, Rect.full(10, 3)
      tree.layout_if_needed

      tile.value = 2
      expect(tree.dirty?).to be_true
    end

    it "leaves the tree alone when the value is set to what it already was" do
      tile = whole 1, "n"
      tree = Layout::Tree.new tile, Rect.full(10, 3)
      tree.layout_if_needed

      tile.value = 1
      expect(tree.dirty?).to be_false
    end

    it "leaves the tree alone when only the colour changes" do
      tile = whole 1, "n"
      tree = Layout::Tree.new tile, Rect.full(10, 3)
      tree.layout_if_needed

      tile.thresholds = [{0.0, red}]
      expect(tree.dirty?).to be_false
    end
  end
end
