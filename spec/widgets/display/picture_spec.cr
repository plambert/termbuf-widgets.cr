require "../../spec_helper"

# A store built for a terminal that draws pictures, and one built for a
# terminal that does not. Both record what was placed; only the first sends
# anything.
module Fixtures
  # An image store over a terminal that draws pictures.
  def self.graphical_store : TermBuf::ImageStore
    TermBuf::ImageStore.new TermBuf::Capabilities.new(TermBuf::Capability::KittyGraphics)
  end

  # One over a terminal that does not.
  def self.plain_store : TermBuf::ImageStore
    TermBuf::ImageStore.new TermBuf::Capabilities::NONE
  end

  # Four red pixels, which is as small as a picture gets.
  def self.pixels : TermBuf::Image
    TermBuf::Image.rgb Bytes[255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0], 2, 2
  end
end

Spectator.describe TermBuf::Widgets::Picture do
  alias Picture = TermBuf::Widgets::Picture

  # A root for *shot* to be laid out inside, since a tree's own root is given
  # the whole screen whatever size it asked for.
  def boxed(shot : Picture) : TermBuf::Widgets::Panel
    root = TermBuf::Widgets::Panel.new width: Layout::Sizing.grow,
      height: Layout::Sizing.grow
    root.add shot
    root
  end

  describe "the box" do
    it "takes the cell size it was given" do
      shot = Picture.new Fixtures.pixels, columns: 12, rows: 4
      Fixtures.painted boxed(shot), 30, 8

      expect(shot.rect.width).to eq 12
      expect(shot.rect.height).to eq 4
    end

    it "grows to whatever it is given when it was told no size" do
      shot = Picture.new Fixtures.pixels
      Fixtures.painted shot, 30, 8

      expect(shot.rect.width).to eq 30
      expect(shot.rect.height).to eq 8
    end
  end

  describe "#place_images" do
    it "asks for the picture across the box it was given" do
      store = Fixtures.graphical_store
      shot = Picture.new Fixtures.pixels, columns: 12, rows: 4
      Fixtures.painted boxed(shot), 30, 8, images: store

      expect(store.placements.size).to eq 1
      expect(store.placements.first.bounds).to eq Rect.new(0, 0, 12, 4)
      expect(store.placements.first.z).to eq 0
    end

    it "asks for it at the depth it was given" do
      store = Fixtures.graphical_store
      shot = Picture.new Fixtures.pixels, columns: 4, rows: 2, z: -1
      Fixtures.painted shot, 30, 8, images: store

      expect(store.placements.first.z).to eq -1
      expect(store.placements.first.under_text?).to be_true
    end

    it "asks for nothing when it holds no picture" do
      store = Fixtures.graphical_store
      Fixtures.painted Picture.new(alt: "nothing"), 30, 8, images: store

      expect(store.placements).to be_empty
    end

    it "asks for nothing at all where there is no store" do
      shot = Picture.new Fixtures.pixels, columns: 4, rows: 2
      expect(Fixtures.render(shot, 30, 8)).to be_a Array(String)
    end

    it "sends no bytes to a terminal that draws no pictures" do
      store = Fixtures.plain_store
      shot = Picture.new Fixtures.pixels, columns: 4, rows: 2
      Fixtures.painted boxed(shot), 30, 8, images: store

      expect(store.placements.size).to eq 1
      expect(store.pending?).to be_false
    end
  end

  describe "the alt text" do
    it "goes on the screen so a terminal without pictures shows something" do
      shot = Picture.new Fixtures.pixels, columns: 12, rows: 4, alt: "a graph"
      lines = Fixtures.render boxed(shot), 30, 8

      expect(lines.first).to eq "  a graph"
    end

    it "is cut to the box it was given" do
      shot = Picture.new columns: 6, rows: 2, alt: "a very long caption"

      expect(Fixtures.render(boxed(shot), 30, 8).first).to eq "a ver…"
    end

    it "draws nothing at all when there is none" do
      shot = Picture.new Fixtures.pixels, columns: 6, rows: 2

      expect(Fixtures.render(shot, 30, 2).all?(&.empty?)).to be_true
    end
  end
end
