require "../spec_helper"

Spectator.describe TermBuf::Widgets::Scrolls::Margin do
  alias Margin = TermBuf::Widgets::Scrolls::Margin

  describe "#rows_for" do
    it "keeps nothing for none, whatever the height" do
      expect(Margin.none.rows_for(1)).to eq 0
      expect(Margin.none.rows_for(40)).to eq 0
    end

    it "keeps a fixed number of rows when the window is tall enough" do
      expect(Margin.rows(2).rows_for(10)).to eq 2
    end

    it "keeps a share of the window, rounded down" do
      expect(Margin.share(0.25).rows_for(20)).to eq 5
      expect(Margin.share(0.25).rows_for(10)).to eq 2
      expect(Margin.share(0.25).rows_for(3)).to eq 0
    end

    it "keeps nothing in a window of one row" do
      expect(Margin.rows(3).rows_for(1)).to eq 0
      expect(Margin.share(0.5).rows_for(1)).to eq 0
    end

    it "keeps nothing in a window of two rows, where one margin would leave no room for the other" do
      expect(Margin.rows(3).rows_for(2)).to eq 0
      expect(Margin.share(0.5).rows_for(2)).to eq 0
    end

    it "keeps one row in a window of three, which is all that leaves a row for the selection" do
      expect(Margin.rows(3).rows_for(3)).to eq 1
      expect(Margin.share(0.5).rows_for(3)).to eq 1
    end

    it "holds a share of one half to what leaves the selection a row" do
      expect(Margin.share(0.5).rows_for(10)).to eq 4
      expect(Margin.share(0.5).rows_for(11)).to eq 5
    end

    it "holds a count that would be more than half the window" do
      expect(Margin.rows(20).rows_for(10)).to eq 4
    end

    it "holds a share that would be more than half the window" do
      expect(Margin.share(0.9).rows_for(10)).to eq 4
      expect(Margin.share(7.0).rows_for(10)).to eq 4
    end

    it "clamps what makes no sense instead of raising" do
      expect(Margin.rows(-3).rows_for(10)).to eq 0
      expect(Margin.share(-0.5).rows_for(10)).to eq 0
      expect(Margin.share(Float64::NAN).rows_for(10)).to eq 0
      expect(Margin.share(Float64::INFINITY).rows_for(10)).to eq 4
      expect(Margin.rows(2).rows_for(0)).to eq 0
      expect(Margin.rows(2).rows_for(-5)).to eq 0
    end
  end

  it "compares equal to one that says the same" do
    expect(Margin.share(0.25)).to eq Margin.share(0.25)
    expect(Margin.none).to eq Margin.rows(0)
    expect(Margin.rows(2)).not_to eq Margin.none
  end
end
