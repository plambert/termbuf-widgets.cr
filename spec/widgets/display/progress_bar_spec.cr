require "../../spec_helper"

Spectator.describe TermBuf::Widgets::ProgressBar do
  alias ProgressBar = TermBuf::Widgets::ProgressBar
  alias Style = TermBuf::Style
  alias Color = TermBuf::Color

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }

  # A bar drawn in characters a spec can read back off the screen.
  def plain(value : Float64 = 0.0) : ProgressBar
    bar = ProgressBar.new value
    bar.filled_char = '#'
    bar.empty_char = '.'
    bar
  end

  describe "#value=" do
    it "holds the value inside zero and one" do
      bar = ProgressBar.new

      bar.value = 1.7
      expect(bar.value).to eq 1.0

      bar.value = -0.3
      expect(bar.value).to eq 0.0
    end

    it "takes an integer as well as a fraction" do
      bar = ProgressBar.new
      bar.value = 1

      expect(bar.value).to eq 1.0
    end

    it "leaves the tree alone, because no geometry comes of it" do
      bar = ProgressBar.new
      tree = Layout::Tree.new bar, Rect.full(10, 3)
      tree.layout_if_needed

      bar.value = 0.5
      expect(tree.dirty?).to be_false
    end
  end

  describe "#filled_cells" do
    {% for row in [{0.0, 10, 0}, {0.25, 10, 3}, {0.5, 10, 5}, {1.0, 10, 10},
                   {0.5, 7, 4}, {0.5, 1, 1}, {0.1, 3, 0}] %}
      it "fills {{ row[2] }} of {{ row[1] }} at {{ row[0] }}" do
        expect(ProgressBar.new({{ row[0] }}).filled_cells({{ row[1] }})).to eq {{ row[2] }}
      end
    {% end %}

    it "fills nothing in no room at all" do
      expect(ProgressBar.new(1.0).filled_cells(0)).to eq 0
    end
  end

  describe "#draw" do
    it "draws the filled run and then the empty one" do
      expect(Fixtures.render(plain(0.4), 10, 1)).to eq ["####......"]
    end

    it "draws nothing filled at zero" do
      expect(Fixtures.render(plain(0.0), 6, 1)).to eq ["......"]
    end

    it "fills every cell at one" do
      expect(Fixtures.render(plain(1.0), 6, 1)).to eq ["######"]
    end

    it "stays on one row in a taller box" do
      expect(Fixtures.render(plain(0.5), 4, 3)).to eq ["##..", "", ""]
    end
  end

  describe "the label" do
    it "puts the percentage in the middle" do
      bar = plain 0.5
      bar.label = ProgressBar::Placement::Centre

      expect(Fixtures.render(bar, 10, 1)).to eq ["###50%...."]
    end

    it "puts the percentage against the right edge" do
      bar = plain 0.5
      bar.label = ProgressBar::Placement::End

      expect(Fixtures.render(bar, 10, 1)).to eq ["#####..50%"]
    end

    it "says what it was told to say instead of a percentage" do
      bar = plain 0.5
      bar.label = ProgressBar::Placement::End
      bar.label_text = "wait"

      expect(Fixtures.render(bar, 10, 1)).to eq ["#####.wait"]
    end

    it "keeps the colour the bar put behind it" do
      bar = plain 1.0
      bar.filled_style = Style::DEFAULT.bg Color.rgb(0x20, 0x40, 0x80)
      bar.label = ProgressBar::Placement::Centre
      painted = Fixtures.painted bar, 10, 1

      style = Fixtures.style_at painted, 4, 0
      expect(style.background).to eq Color.rgb(0x20, 0x40, 0x80)
      expect(style.has?(TermBuf::Attributes::Bold)).to be_true
    end

    it "leaves the label off when there is no room for it" do
      bar = plain 1.0
      bar.label = ProgressBar::Placement::Centre

      expect(Fixtures.render(bar, 2, 1)).to eq ["##"]
    end
  end

  describe "#blend" do
    it "gives each filled cell its own colour along the ramp" do
      bar = plain 1.0
      ramp = TermBuf::Gradient.new Color.rgb(0, 0, 0), Color.rgb(0, 0, 255),
        Rect.full(5, 1), :horizontal
      bar.blend = ramp.background
      painted = Fixtures.painted bar, 5, 1

      colours = (0...5).map { |column| Fixtures.style_at(painted, column, 0).background }

      expect(colours.first).to eq Color.rgb(0, 0, 0)
      expect(colours.last).to eq Color.rgb(0, 0, 255)
      expect(colours.uniq.size).to eq 5
    end

    it "leaves the empty run out of the ramp" do
      bar = plain 0.5
      ramp = TermBuf::Gradient.new Color.rgb(255, 0, 0), Color.rgb(255, 0, 0),
        Rect.full(4, 1), :horizontal
      bar.blend = ramp.background
      painted = Fixtures.painted bar, 4, 1

      expect(Fixtures.style_at(painted, 0, 0).background).to eq Color.rgb(255, 0, 0)
      expect(Fixtures.style_at(painted, 3, 0).background).to eq Color.default
    end
  end

  describe "indeterminate" do
    it "puts the block at the left edge at phase zero" do
      bar = plain
      bar.indeterminate = true
      bar.block_width = 3

      expect(Fixtures.render(bar, 10, 1)).to eq ["###......."]
    end

    it "puts the block at the right edge at phase one" do
      bar = plain
      bar.indeterminate = true
      bar.block_width = 3
      bar.phase = 1.0

      expect(Fixtures.render(bar, 10, 1)).to eq [".......###"]
    end

    it "slides the block along with the phase" do
      bar = plain
      bar.indeterminate = true
      bar.block_width = 2
      bar.phase = 0.5

      expect(Fixtures.render(bar, 10, 1)).to eq ["....##...."]
    end

    it "holds the phase inside zero and one" do
      bar = plain
      bar.indeterminate = true
      bar.block_width = 2
      bar.phase = 4.0

      expect(bar.block_at(10)).to eq({8, 2})
    end

    it "cuts a block wider than the bar down to it" do
      bar = plain
      bar.indeterminate = true
      bar.block_width = 20

      expect(bar.block_at(6)).to eq({0, 6})
    end

    it "ignores the value it was given" do
      bar = plain 1.0
      bar.indeterminate = true
      bar.block_width = 2

      expect(Fixtures.render(bar, 6, 1)).to eq ["##...."]
    end
  end

  describe "in a layout" do
    it "grows to the width it is given and stays one row" do
      root = TermBuf::Widgets::Panel.new width: Sizing.grow, height: Sizing.grow
      bar = ProgressBar.new
      root.add bar

      Layout::Tree.new(root, Rect.full(18, 4)).layout

      expect(bar.rect.width).to eq 18
      expect(bar.rect.height).to eq 1
    end

    it "takes its preferred width when it is told to fit" do
      root = TermBuf::Widgets::Panel.new width: Sizing.grow, height: Sizing.grow
      bar = ProgressBar.new width: Sizing.fit
      bar.preferred_width = 12
      root.add bar

      Layout::Tree.new(root, Rect.full(40, 4)).layout
      expect(bar.rect.width).to eq 12
    end
  end
end
