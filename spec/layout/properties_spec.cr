require "../spec_helper"

Spectator.describe "layout invariants" do
  # Fixed seeds, so a failure is reproducible; widen the range when hunting.
  sample [1_u64, 2_u64, 3_u64, 4_u64, 5_u64, 6_u64, 7_u64, 8_u64,
          9_u64, 10_u64, 11_u64, 12_u64, 13_u64, 14_u64, 15_u64, 16_u64] do |seed|
    it "hold across random trees and screens (seed #{seed})" do
      random = Random.new seed
      generator = Fixtures::Generator.new random

      12.times do |round|
        screen = generator.screen
        tree = Layout::Tree.new generator.tree, screen
        tree.layout

        if failure = Fixtures::Invariants.check(tree)
          fail "seed #{seed}, tree #{round}, screen #{screen}: #{failure}"
        end

        settled = Fixtures::Invariants.rects tree

        tree.layout
        if Fixtures::Invariants.rects(tree) != settled
          fail "seed #{seed}, tree #{round}, screen #{screen}: laying out again moved something"
        end

        tree.invalidate
        tree.layout_if_needed
        if Fixtures::Invariants.rects(tree) != settled
          fail "seed #{seed}, tree #{round}, screen #{screen}: invalidating and laying out again moved something"
        end
      end
    end
  end
end
