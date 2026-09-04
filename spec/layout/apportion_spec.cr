require "../spec_helper"

Spectator.describe Layout::Engine do
  alias Slot = Layout::Slot

  def slots(weights : Array(Int32),
            mins : Array(Int32)? = nil,
            maxes : Array(Int32)? = nil) : Array(Slot)
    weights.map_with_index do |weight, index|
      Slot.new weight, mins.try(&.[index]) || 0, maxes.try(&.[index]) || Int32::MAX
    end
  end

  describe ".apportion" do
    context "with nothing in the way" do
      it "divides evenly and sums to the total exactly" do
        result = Layout::Engine.apportion slots([1, 1, 1]), 10
        expect(result).to eq [3, 4, 3]
        expect(result.sum).to eq 10
      end

      it "divides by weight" do
        result = Layout::Engine.apportion slots([1, 3]), 12
        expect(result).to eq [3, 9]
      end

      it "sums to the total at every size" do
        (0..64).each do |total|
          result = Layout::Engine.apportion slots([2, 3, 5]), total
          expect(result.sum).to eq total
        end
      end

      it "reads shares off boundaries, so the error never accumulates" do
        result = Layout::Engine.apportion slots([1, 1, 1, 1, 1, 1, 1]), 10
        expect(result).to eq [1, 2, 1, 2, 1, 2, 1]
        expect(result.sum).to eq 10
      end
    end

    context "against a denominator of its own" do
      it "gives each slot its percent of the total" do
        result = Layout::Engine.apportion slots([25, 25, 25, 25]), 10, 100
        expect(result).to eq [3, 2, 3, 2]
      end

      it "leaves the rest alone when the shares do not add up to the whole" do
        result = Layout::Engine.apportion slots([25, 25]), 10, 100
        expect(result).to eq [3, 2]
      end
    end

    context "when a slot lands below its minimum" do
      it "pins it and divides the rest again" do
        result = Layout::Engine.apportion slots([1, 1, 1], mins: [5, 1, 1]), 10
        expect(result).to eq [5, 3, 2]
        expect(result.sum).to eq 10
      end

      it "divides what is left over among the slots still open" do
        result = Layout::Engine.apportion slots([1, 1, 1], mins: [0, 4, 0]), 9
        expect(result).to eq [3, 4, 2]
        expect(result.sum).to eq 9
      end

      it "overflows the total rather than breaking a minimum" do
        result = Layout::Engine.apportion slots([1, 1], mins: [4, 4]), 3
        expect(result).to eq [4, 4]
      end
    end

    context "when a slot lands above its maximum" do
      it "pins it and hands the surplus to the others" do
        result = Layout::Engine.apportion slots([1, 1, 1], maxes: [2, Int32::MAX, Int32::MAX]), 10
        expect(result).to eq [2, 4, 4]
        expect(result.sum).to eq 10
      end

      it "pins several in one round" do
        result = Layout::Engine.apportion slots([1, 1, 1, 1], maxes: [1, 2, 3, Int32::MAX]), 20
        expect(result).to eq [1, 2, 3, 14]
        expect(result.sum).to eq 20
      end

      it "keeps a floor that sits above its own ceiling" do
        result = Layout::Engine.apportion slots([1, 1], mins: [6, 0], maxes: [3, Int32::MAX]), 10
        expect(result).to eq [6, 4]
      end
    end

    context "with both bounds cascading" do
      it "settles inside every one of them" do
        result = Layout::Engine.apportion(
          slots([1, 1, 1, 1], mins: [0, 0, 0, 5], maxes: [2, Int32::MAX, Int32::MAX, Int32::MAX]),
          12)
        expect(result).to eq [2, 3, 2, 5]
        expect(result.sum).to eq 12
      end

      it "ends on a set every one of which is pinned" do
        count = 40
        mins = Array.new(count) { |index| index }
        maxes = Array.new(count) { |index| index + 1 }
        result = Layout::Engine.apportion slots(Array.new(count, 1), mins: mins, maxes: maxes), 100

        expect(result.size).to eq count
        result.each_with_index do |value, index|
          expect(value).to be >= mins[index]
          expect(value).to be <= maxes[index]
        end
      end
    end

    context "with nothing to divide" do
      it "gives every slot nothing when the total is zero" do
        expect(Layout::Engine.apportion(slots([1, 2, 3]), 0)).to eq [0, 0, 0]
      end

      it "raises each slot to its minimum when the total is zero" do
        expect(Layout::Engine.apportion(slots([1, 1], mins: [2, 3]), 0)).to eq [2, 3]
      end

      it "gives every slot nothing when no slot claims any weight" do
        expect(Layout::Engine.apportion(slots([0, 0, 0]), 10)).to eq [0, 0, 0]
      end

      it "still honours minimums when no slot claims any weight" do
        expect(Layout::Engine.apportion(slots([0, 0], mins: [3, 0]), 10)).to eq [3, 0]
      end

      it "returns nothing at all for no slots" do
        expect(Layout::Engine.apportion(Array(Slot).new, 10)).to be_empty
      end
    end
  end
end
