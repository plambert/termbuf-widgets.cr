require "../../spec_helper"

Spectator.describe TermBuf::Widgets::FormattedNumber do
  alias FormattedNumber = TermBuf::Widgets::FormattedNumber

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }

  describe "#text" do
    {% for row in [{0, 0, "0"},
                   {1234, 0, "1,234"},
                   {999, 0, "999"},
                   {1000, 0, "1,000"},
                   {1234567, 0, "1,234,567"},
                   {-1234, 0, "-1,234"},
                   {1234.5678, 2, "1,234.57"},
                   {0.5, 1, "0.5"},
                   {-0.04, 1, "-0.0"}] %}
      it "draws {{ row[0] }} at {{ row[1] }} decimals as {{ row[2].id }}" do
        number = FormattedNumber.new {{ row[0] }}, decimals: {{ row[1] }}
        expect(number.text).to eq {{ row[2] }}
      end
    {% end %}

    it "leaves the digits ungrouped when there is no separator" do
      expect(FormattedNumber.new(1234567, grouping: "").text).to eq "1234567"
    end

    it "takes the separator and the point it was given" do
      number = FormattedNumber.new 1234.5, decimals: 1, grouping: ".", point: ","
      expect(number.text).to eq "1.234,5"
    end

    it "groups by the size it was given" do
      number = FormattedNumber.new 123456, group_size: 2
      expect(number.text).to eq "12,34,56"
    end

    it "puts a plus on a positive number when it is asked to" do
      expect(FormattedNumber.new(12, sign: true).text).to eq "+12"
    end

    it "leaves zero without a sign" do
      expect(FormattedNumber.new(0, sign: true).text).to eq "0"
    end

    it "keeps the minus on a negative number whatever the sign flag says" do
      expect(FormattedNumber.new(-12, sign: false).text).to eq "-12"
    end

    it "puts the unit after the number" do
      expect(FormattedNumber.new(120, unit: "ms").text).to eq "120 ms"
    end

    it "closes the gap before the unit when it is told to" do
      expect(FormattedNumber.new(120, unit: "%", unit_space: false).text).to eq "120%"
    end
  end

  describe "the arguments it refuses" do
    it "will not take negative decimals" do
      expect { FormattedNumber.new 1, decimals: -1 }.to raise_error(ArgumentError, /decimals/)
    end

    it "will not take a group size below one" do
      expect { FormattedNumber.new 1, group_size: 0 }.to raise_error(ArgumentError, /group size/)
    end
  end

  describe "#intrinsic_width" do
    it "wants exactly its own text" do
      expect(FormattedNumber.new(1234567, unit: "ms").intrinsic_width(policy).preferred).to eq 12
    end

    it "survives in a single cell" do
      expect(FormattedNumber.new(1234567).intrinsic_width(policy).min).to eq 1
    end
  end

  describe "#height_for_width" do
    it "is one row however wide it is" do
      expect(FormattedNumber.new(1).height_for_width(3, policy)).to eq 1
    end
  end

  describe "#draw" do
    it "writes the number" do
      expect(Fixtures.render(FormattedNumber.new(1234567), 12, 1)).to eq ["1,234,567"]
    end

    it "marks a number it had to cut" do
      expect(Fixtures.render(FormattedNumber.new(1234567), 6, 1)).to eq ["1,234…"]
    end

    it "puts the number against the right edge" do
      number = FormattedNumber.new 42, align: TermBuf::Unicode::Align::Right
      expect(Fixtures.render(number, 6, 1)).to eq ["    42"]
    end
  end

  describe "in a layout" do
    it "fits its own text" do
      root = TermBuf::Widgets::Panel.new width: Sizing.grow, height: Sizing.grow
      number = FormattedNumber.new 1234, unit: "ms"
      root.add number

      Layout::Tree.new(root, Rect.full(30, 3)).layout

      expect(number.rect.width).to eq 8
      expect(number.rect.height).to eq 1
    end

    it "marks the tree dirty when the decimals change" do
      number = FormattedNumber.new 1.5
      tree = Layout::Tree.new number, Rect.full(10, 3)
      tree.layout_if_needed

      number.decimals = 2
      expect(tree.dirty?).to be_true
    end
  end
end
