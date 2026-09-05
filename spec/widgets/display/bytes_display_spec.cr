require "../../spec_helper"

Spectator.describe TermBuf::Widgets::BytesDisplay do
  alias BytesDisplay = TermBuf::Widgets::BytesDisplay

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }

  describe "#text in IEC units" do
    {% for row in [{0, "0 B"},
                   {1, "1 B"},
                   {1023, "1023 B"},
                   {1024, "1.0 KiB"},
                   {1536, "1.5 KiB"},
                   {1048576, "1.0 MiB"},
                   {1048575, "1.0 MiB"},
                   {1073741824, "1.0 GiB"},
                   {-2048, "-2.0 KiB"}] %}
      it "draws {{ row[0] }} as {{ row[1].id }}" do
        expect(BytesDisplay.new({{ row[0] }}).text).to eq {{ row[1] }}
      end
    {% end %}
  end

  describe "#text in SI units" do
    {% for row in [{999, "999 B"},
                   {1000, "1.0 KB"},
                   {1500, "1.5 KB"},
                   {1500000, "1.5 MB"},
                   {1000000000, "1.0 GB"}] %}
      it "draws {{ row[0] }} as {{ row[1].id }}" do
        expect(BytesDisplay.new({{ row[0] }}, standard: BytesDisplay::Standard::SI).text).to eq {{ row[1] }}
      end
    {% end %}
  end

  describe "#precision" do
    it "shows as many decimals as it was told to" do
      expect(BytesDisplay.new(1536, precision: 3).text).to eq "1.500 KiB"
    end

    it "shows none at all at zero" do
      expect(BytesDisplay.new(1536, precision: 0).text).to eq "2 KiB"
    end

    it "leaves bytes whole whatever the precision" do
      expect(BytesDisplay.new(512, precision: 3).text).to eq "512 B"
    end

    it "will not take a negative precision" do
      expect { BytesDisplay.new 1, precision: -1 }.to raise_error(ArgumentError, /precision/)
    end
  end

  describe "#scaled" do
    it "steps up rather than drawing a whole base in the smaller unit" do
      amount, unit = BytesDisplay.new(1048575).scaled

      expect(unit).to eq "MiB"
      expect(amount).to be_close(1.0, 0.001)
    end

    it "stops at the largest unit it knows" do
      _, unit = BytesDisplay.new(Int64::MAX).scaled
      expect(unit).to eq "EiB"
    end
  end

  describe "#space?" do
    it "closes the gap before the unit when it is told to" do
      expect(BytesDisplay.new(2048, space: false).text).to eq "2.0KiB"
    end
  end

  describe "#intrinsic_width" do
    it "wants exactly its own text" do
      expect(BytesDisplay.new(1536).intrinsic_width(policy).preferred).to eq 7
    end

    it "survives in a single cell" do
      expect(BytesDisplay.new(1536).intrinsic_width(policy).min).to eq 1
    end
  end

  describe "#draw" do
    it "writes the count and its unit" do
      expect(Fixtures.render(BytesDisplay.new(1536), 12, 1)).to eq ["1.5 KiB"]
    end

    it "marks a count it had to cut" do
      expect(Fixtures.render(BytesDisplay.new(1536), 5, 1)).to eq ["1.5 …"]
    end
  end

  describe "in a layout" do
    it "fits its own text and stays one row" do
      root = TermBuf::Widgets::Panel.new width: Sizing.grow, height: Sizing.grow
      count = BytesDisplay.new 1536
      root.add count

      Layout::Tree.new(root, Rect.full(30, 3)).layout

      expect(count.rect.width).to eq 7
      expect(count.rect.height).to eq 1
    end

    it "marks the tree dirty when the count changes size on screen" do
      count = BytesDisplay.new 512
      tree = Layout::Tree.new count, Rect.full(20, 3)
      tree.layout_if_needed

      count.bytes = 1536
      expect(tree.dirty?).to be_true
    end
  end
end
