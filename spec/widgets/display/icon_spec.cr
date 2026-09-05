require "../../spec_helper"
require "./picture_spec"

Spectator.describe TermBuf::Widgets::Icon do
  alias Icon = TermBuf::Widgets::Icon

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }
  let(cjk) { TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2 }

  describe "#reserved" do
    it "takes the glyph's own width when it was given no count" do
      expect(Icon.new("★").reserved).to eq 1
      expect(Icon.new("📁").reserved).to eq 2
    end

    it "takes the count it was given" do
      expect(Icon.new("★", cells: 2).reserved).to eq 2
    end
  end

  describe "#glyph_for" do
    it "keeps a glyph that measures what the icon reserved" do
      mark = Icon.new "★", fallback: "*"

      expect(mark.glyph_for(policy)).to eq "★"
    end

    it "takes the fallback where the glyph would come out wider" do
      mark = Icon.new "★", fallback: "*"

      expect(mark.glyph_for(cjk)).to eq "*"
    end

    it "leaves a glyph that is two cells everywhere alone" do
      folder = Icon.new "📁", fallback: "[]"

      expect(folder.glyph_for(policy)).to eq "📁"
      expect(folder.glyph_for(cjk)).to eq "📁"
    end

    it "draws the glyph whatever it measures when there is no fallback" do
      mark = Icon.new "★"

      expect(mark.glyph_for(cjk)).to eq "★"
    end
  end

  describe "#draw" do
    it "puts the glyph on the screen" do
      expect(Fixtures.render(Icon.new("*"), 6, 1).first).to eq "*"
    end

    it "puts the fallback there under a policy that would draw it ragged" do
      mark = Icon.new "★", fallback: "*"

      expect(Fixtures.render(mark, 6, 1, policy: cjk).first).to eq "*"
    end
  end

  describe "the layout" do
    it "asks for the width of the spelling it will draw" do
      mark = Icon.new "★", fallback: "*"

      expect(mark.intrinsic_width(policy).preferred).to eq 1
      expect(mark.intrinsic_width(cjk).preferred).to eq 1
    end

    it "asks for the two cells an emoji takes" do
      expect(Icon.new("📁").intrinsic_width(policy).preferred).to eq 2
    end
  end

  describe "a picture over it" do
    it "asks for the picture across its own cells" do
      store = Fixtures.graphical_store
      mark = Icon.new "*", image: Fixtures.pixels
      Fixtures.painted mark, 6, 1, images: store

      expect(store.placements.size).to eq 1
      expect(store.placements.first.bounds).to eq Rect.new(0, 0, 6, 1)
    end

    it "asks for nothing when it holds none" do
      store = Fixtures.graphical_store
      Fixtures.painted Icon.new("*"), 6, 1, images: store

      expect(store.placements).to be_empty
    end

    it "draws the glyph either way, since the picture covers it" do
      store = Fixtures.graphical_store
      mark = Icon.new "*", image: Fixtures.pixels
      buffer = Fixtures.painted mark, 6, 1, images: store

      expect(Fixtures.text_of(buffer).first).to eq "*"
    end
  end
end
