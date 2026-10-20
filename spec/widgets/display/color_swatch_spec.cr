require "../../spec_helper"
require "../input/input_harness_spec"

Spectator.describe TermBuf::Widgets::ColorSwatch do
  alias ColorSwatch = TermBuf::Widgets::ColorSwatch
  alias Depth = TermBuf::Widgets::Depth
  alias Color = TermBuf::Color

  let(blue) { Color.rgb 0x3080C0 }

  # The background a terminal without true color would be sent for one cell.
  def encoded_background(buffer : TermBuf::Buffer, x : Int32) : Color
    encoder = TermBuf::Encoder.new buffer.styles, TermBuf::Capabilities::XTERM,
      buffer.width, buffer.height
    encoder.effective(buffer.back[x, 0].style).background
  end

  describe "side by side" do
    it "draws the bar and then the value, the bar taking the rest" do
      swatch = ColorSwatch.new blue
      buffer = Fixtures.painted swatch, 20, 1

      expect(Fixtures.text_of(buffer)[0]).to eq "#{" " * 13}#3080c0"
      expect(Fixtures.style_at(buffer, 0, 0).background).to eq blue
      expect(Fixtures.style_at(buffer, 11, 0).background).to eq blue
      expect(Fixtures.style_at(buffer, 12, 0).background).to eq Color.default
    end

    it "asks for the value and the shortest bar" do
      swatch = ColorSwatch.new blue, least_bar: 3
      intrinsic = swatch.intrinsic_width TermBuf::Unicode::WidthPolicy::DEFAULT

      expect(swatch.narrow).to eq 7 + 1 + 3
      expect(intrinsic.preferred).to eq swatch.narrow
      expect(intrinsic.min).to eq 1
    end
  end

  describe "over the bar" do
    it "writes the value over the bar when there is no room beside it" do
      swatch = ColorSwatch.new blue
      buffer = Fixtures.painted swatch, 9, 1

      expect(Fixtures.text_of(buffer)[0]).to eq " #3080c0"
      expect(Fixtures.style_at(buffer, 0, 0).background).to eq blue
      expect(Fixtures.style_at(buffer, 1, 0).background).to eq blue
      expect(Fixtures.style_at(buffer, 8, 0).background).to eq blue
    end

    it "writes black on a light color" do
      light = Color.rgb 0xFFE070
      buffer = Fixtures.painted ColorSwatch.new(light), 9, 1

      expect(Fixtures.style_at(buffer, 1, 0).foreground).to eq Color.rgb(0, 0, 0)
    end

    it "writes white on a dark color" do
      dark = Color.rgb 0x101060
      buffer = Fixtures.painted ColorSwatch.new(dark), 9, 1

      expect(Fixtures.style_at(buffer, 1, 0).foreground).to eq Color.rgb(255, 255, 255)
    end

    it "uses palette black and white at 256 colors" do
      light = ColorSwatch.new Color.rgb(0xFFE070), depth: Depth::Indexed256
      dark = ColorSwatch.new Color.rgb(0x101060), depth: Depth::Indexed256

      expect(Fixtures.style_at(Fixtures.painted(light, 12, 1), 1, 0).foreground).to eq Color.indexed(16)
      expect(Fixtures.style_at(Fixtures.painted(dark, 12, 1), 1, 0).foreground).to eq Color.indexed(231)
    end
  end

  describe "the bar alone" do
    it "draws only the bar when the value does not fit" do
      buffer = Fixtures.painted ColorSwatch.new(blue), 5, 1

      expect(Fixtures.text_of(buffer)[0]).to eq ""
      expect(Fixtures.style_at(buffer, 4, 0).background).to eq blue
    end
  end

  describe "at 256 colors" do
    it "shows the index the encoder sends to a 256 color terminal" do
      true_color = Fixtures.painted ColorSwatch.new(blue), 20, 1
      sent = encoded_background true_color, 0

      swatch = ColorSwatch.new blue, depth: Depth::Indexed256
      buffer = Fixtures.painted swatch, 24, 1
      red, green, blue_level = sent.channels

      expect(sent.indexed?).to be_true
      expect(swatch.value_text).to eq "#%02x%02x%02x %d" % {red, green, blue_level, sent.index}
      expect(Fixtures.text_of(buffer)[0]).to end_with swatch.value_text
      expect(Fixtures.style_at(buffer, 0, 0).background).to eq sent
    end

    it "shows an indexed color's index and the palette's value for it" do
      swatch = ColorSwatch.new Color.indexed(208)

      expect(swatch.value_text).to eq "#ff8700 208"
    end

    it "calls the terminal's own color default" do
      expect(ColorSwatch.new(Color.default).value_text).to eq "default"
    end
  end

  describe "#color=" do
    it "draws the new color" do
      swatch = ColorSwatch.new blue
      swatch.color = Color.rgb 0xC03020

      expect(Fixtures.render(swatch, 20, 1)[0]).to end_with "#c03020"
    end

    it "leaves the layout alone while the value keeps its width" do
      swatch = ColorSwatch.new blue
      tree = Layout::Tree.new swatch, Rect.full(20, 1)
      tree.layout_if_needed

      swatch.color = Color.rgb 0xC03020
      expect(tree.dirty?).to be_false
    end

    it "lays out again when the value changes width" do
      swatch = ColorSwatch.new blue, depth: Depth::Indexed256
      swatch.color = Color.indexed 16
      tree = Layout::Tree.new swatch, Rect.full(20, 1)
      tree.layout_if_needed

      swatch.color = Color.indexed 208
      expect(tree.dirty?).to be_true
    end

    it "emits nothing" do
      root = Fixtures::MessageLog.new
      swatch = ColorSwatch.new blue
      root.add swatch
      made = Fixtures::TestApp.new root, 20, 2
      made.frame

      swatch.color = Color.rgb 0xC03020
      Fixtures.settle made
      expect(root.seen).to be_empty
    end
  end
end
