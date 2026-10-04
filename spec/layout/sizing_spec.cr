require "../spec_helper"

Spectator.describe Layout::Sizing do
  alias Basis = Layout::Sizing::Basis

  describe "percentage bounds" do
    it "takes the parent as the basis unless told otherwise" do
      sizing = Sizing.fit.with_max_percent 25

      expect(sizing.max_percent).to eq 25
      expect(sizing.max_basis).to eq Basis::Parent
    end

    it "keeps a basis of its own for each bound" do
      sizing = Sizing.fit.with_min_percent(30, of: :screen).with_max_percent(25)

      expect(sizing.min_basis).to eq Basis::Screen
      expect(sizing.max_basis).to eq Basis::Parent
    end

    it "keeps the percentages through a change to the cells" do
      sizing = Sizing.fit.with_max_percent(25, of: :component).with_min(6).with_max(40)

      expect(sizing.min).to eq 6
      expect(sizing.max).to eq 40
      expect(sizing.max_percent).to eq 25
      expect(sizing.max_basis).to eq Basis::Component
    end

    it "keeps the cells through a change to the percentages" do
      sizing = Sizing.grow(2, min: 3, max: 9).with_min_percent 10

      expect({sizing.mode, sizing.weight, sizing.min, sizing.max}).to eq({Sizing::Mode::Grow, 2, 3, 9})
    end

    it "replaces a percentage set before" do
      sizing = Sizing.fit.with_max_percent(25).with_max_percent(40, of: :screen)

      expect(sizing.max_percent).to eq 40
      expect(sizing.max_basis).to eq Basis::Screen
    end

    it "says whether it has any" do
      expect(Sizing.fit(min: 6).percent_bounds?).to be_false
      expect(Sizing.fit.with_min_percent(0).percent_bounds?).to be_true
      expect(Sizing.fixed(3).with_max_percent(100).percent_bounds?).to be_true
    end
  end

  describe "validation" do
    it "takes 0 and 100" do
      expect { Sizing.fit.with_min_percent(0).with_max_percent(100) }.not_to raise_error
    end

    it "refuses a minimum percent below 0" do
      expect { Sizing.fit.with_min_percent(-1) }.to raise_error(ArgumentError, /minimum percent -1/)
    end

    it "refuses a maximum percent above 100" do
      expect { Sizing.fit.with_max_percent(101) }.to raise_error(ArgumentError, /maximum percent 101/)
    end

    it "refuses one handed straight to the constructor" do
      expect { Sizing.new(Sizing::Mode::Fit, max_percent: 150) }.to raise_error(ArgumentError, /outside 0..100/)
    end
  end

  describe "equality" do
    it "holds between two sizings built the same way" do
      first = Sizing.fit(min: 6).with_max_percent(25, of: :component)
      second = Sizing.fit(min: 6).with_max_percent(25, of: :component)

      expect(first).to eq second
    end

    it "fails on a different percent" do
      expect(Sizing.fit.with_max_percent(25)).not_to eq Sizing.fit.with_max_percent(26)
    end

    it "fails on a different basis" do
      expect(Sizing.fit.with_max_percent(25)).not_to eq Sizing.fit.with_max_percent(25, of: :screen)
    end

    it "fails between a floor and a ceiling of the same percent" do
      expect(Sizing.fit.with_min_percent(25)).not_to eq Sizing.fit.with_max_percent(25)
    end

    it "fails against the same sizing with no percentages" do
      expect(Sizing.fit.with_max_percent(25)).not_to eq Sizing.fit
    end

    it "keeps a widget's layout clean when given an equal sizing" do
      root = Fixtures::Box.new
      root.width = Sizing.fit(min: 6).with_max_percent(25, of: :component)
      tree = Layout::Tree.new root, Rect.full(10, 2)
      tree.layout

      root.width = Sizing.fit(min: 6).with_max_percent(25, of: :component)
      expect(tree.dirty?).to be_false

      root.width = Sizing.fit(min: 6).with_max_percent(30, of: :component)
      expect(tree.dirty?).to be_true
    end
  end

  describe "#bounds" do
    it "answers the cells alone when no basis is known" do
      sizing = Sizing.fit(min: 2, max: 50).with_min_percent(10).with_max_percent(25)

      expect(sizing.bounds).to eq({2, 50})
    end

    it "takes each percentage of its own basis" do
      sizing = Sizing.fit.with_min_percent(10, of: :screen).with_max_percent(25, of: :component)

      expect(sizing.bounds(parent: 1, component: 200, screen: 40)).to eq({4, 50})
    end

    it "rounds a share to the nearest cell" do
      expect(Sizing.fit.with_max_percent(25).bounds(parent: 58)).to eq({0, 15})
      expect(Sizing.fit.with_max_percent(25).bounds(parent: 57)).to eq({0, 14})
    end

    it "keeps the larger floor and the smaller ceiling" do
      sizing = Sizing.fit(min: 6, max: 30).with_min_percent(10).with_max_percent(50)

      expect(sizing.bounds(parent: 40)).to eq({6, 20})
      expect(sizing.bounds(parent: 100)).to eq({10, 30})
    end

    it "lets the floor win when the two cross" do
      sizing = Sizing.fit(max: 5).with_min_percent 50

      expect(sizing.bounds(parent: 40)).to eq({20, 20})
    end

    it "lets the floor win when two percentages cross" do
      sizing = Sizing.fit.with_min_percent(30, of: :screen).with_max_percent(25)

      expect(sizing.bounds(parent: 20, screen: 40)).to eq({12, 12})
    end

    it "lets a percentage cap bring a fixed size down" do
      expect(Sizing.fixed(30).with_max_percent(25).bounds(parent: 40)).to eq({10, 10})
      expect(Sizing.fixed(5).with_max_percent(25).bounds(parent: 40)).to eq({5, 5})
    end

    it "lets a percentage floor raise a fixed size, and win over a cap" do
      expect(Sizing.fixed(5).with_min_percent(25).bounds(parent: 40)).to eq({10, 10})
      expect(Sizing.fixed(30).with_min_percent(50).with_max_percent(25).bounds(parent: 40)).to eq({20, 20})
    end

    it "answers a fixed size's cells when no basis is known" do
      expect(Sizing.fixed(30).with_max_percent(25).bounds).to eq({30, 30})
    end

    it "asks the block only about the bounds that are set" do
      asked = [] of Basis
      Sizing.fit.with_max_percent(25, of: :screen).bounds do |basis|
        asked << basis
        80
      end

      expect(asked).to eq [Basis::Screen]
    end
  end

  describe "#to_s" do
    it "shows the percentages and what they are of" do
      sizing = Sizing.fit(min: 6).with_max_percent(25, of: :component)

      expect(sizing.to_s).to eq "Sizing(Fit min=6 max=25% of component)"
    end

    it "shows them on a fixed sizing" do
      expect(Sizing.fixed(10).with_min_percent(5, of: :screen).to_s).to eq "Sizing(fixed 10 min=5% of screen)"
    end

    it "leaves them out when there are none" do
      expect(Sizing.grow(2, max: 9).to_s).to eq "Sizing(Grow 2 max=9)"
    end
  end
end
