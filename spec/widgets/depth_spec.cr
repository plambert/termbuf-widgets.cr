require "../spec_helper"

Spectator.describe TermBuf::Widgets::Depth do
  alias Depth = TermBuf::Widgets::Depth
  alias Color = TermBuf::Color

  let(blue) { Color.rgb 0x3080C0 }

  describe "#shown" do
    it "leaves a color alone in true color" do
      expect(Depth::TrueColor.shown(blue)).to eq blue
    end

    it "takes the palette index a 256 color terminal draws" do
      expect(Depth::Indexed256.shown(blue)).to eq blue.to_indexed256
    end
  end

  describe "#describe" do
    it "writes the hex in true color" do
      expect(Depth::TrueColor.describe(blue)).to eq "#3080c0"
    end

    it "writes the palette's hex and the index at 256 colors" do
      expect(Depth::Indexed256.describe(blue)).to eq "#5f87af 67"
    end

    it "writes the index of an indexed color at either depth" do
      expect(Depth::TrueColor.describe(Color.indexed(9))).to eq "#ff0000 9"
    end
  end

  describe "#ink" do
    it "is black on white and white on black" do
      expect(Depth::TrueColor.ink(Color.rgb(255, 255, 255))).to eq Color.rgb(0, 0, 0)
      expect(Depth::TrueColor.ink(Color.rgb(0, 0, 0))).to eq Color.rgb(255, 255, 255)
    end

    it "is black on a bright yellow and white on a pure blue" do
      expect(Depth::TrueColor.ink(Color.rgb(0xFFFF00))).to eq Color.rgb(0, 0, 0)
      expect(Depth::TrueColor.ink(Color.rgb(0x0000FF))).to eq Color.rgb(255, 255, 255)
    end

    it "uses cube black and white at 256 colors" do
      expect(Depth::Indexed256.ink(Color.rgb(0xFFFF00))).to eq Color.indexed(16)
      expect(Depth::Indexed256.ink(Color.rgb(0x000080))).to eq Color.indexed(231)
    end
  end
end
