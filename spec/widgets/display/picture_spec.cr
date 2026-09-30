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
  def self.pixels : TermBuf::Pixels
    TermBuf::Pixels.rgb Bytes[255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0], 2, 2
  end

  # A larger one, so a spec can ask for part of it.
  def self.sheet : TermBuf::Pixels
    TermBuf::Pixels.rgb Bytes.new(8 * 8 * 3, 7_u8), 8, 8
  end

  # The escape sequences a store has queued, with the cursor moves left out.
  def self.sequences(store : TermBuf::ImageStore) : Array(String)
    store.take_pending.select &.starts_with? "\e_G"
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
      expect(shot.image).to be_nil
    end

    it "sends no bytes to a terminal that draws no pictures" do
      store = Fixtures.plain_store
      shot = Picture.new Fixtures.pixels, columns: 4, rows: 2
      Fixtures.painted boxed(shot), 30, 8, images: store

      expect(store.placements.size).to eq 1
      expect(store.pending?).to be_false
    end
  end

  # The pixels are a value the widget can hold before there is a terminal in
  # sight. The registry entry cannot exist until a frame arrives with a store.
  describe "the registry entry" do
    it "is made on the first frame and kept afterwards" do
      store = Fixtures.graphical_store
      shot = Picture.new Fixtures.pixels, columns: 4, rows: 2

      expect(shot.image).to be_nil
      Fixtures.painted shot, 30, 8, images: store
      first = shot.image
      expect(first).not_to be_nil

      Fixtures.painted shot, 30, 8, images: store
      expect(shot.image).to be first
      expect(store.images.size).to eq 1
    end

    it "is made again for a store that never saw the picture" do
      shot = Picture.new Fixtures.pixels, columns: 4, rows: 2
      Fixtures.painted shot, 30, 8, images: Fixtures.graphical_store
      first = shot.image

      other = Fixtures.graphical_store
      Fixtures.painted shot, 30, 8, images: other
      expect(shot.image).not_to be first
      expect(other.images.size).to eq 1
    end

    it "goes when the pixels change, and the old picture goes with it" do
      store = Fixtures.graphical_store
      shot = Picture.new Fixtures.pixels, columns: 4, rows: 2
      Fixtures.painted shot, 30, 8, images: store
      old = shot.image
      fail "the first frame registered nothing" unless old
      store.take_pending

      shot.pixels = Fixtures.sheet
      expect(shot.image).to be_nil
      expect(old.forgotten?).to be_true
      expect(Fixtures.sequences(store).join).to contain "a=d,d=I,i=#{old.id}"

      Fixtures.painted shot, 30, 8, images: store
      made = shot.image
      fail "the second frame registered nothing" unless made
      expect(made.id).to be > old.id
      expect(Fixtures.sequences(store).count(&.includes? "a=T")).to eq 1
    end

    it "goes when the picture is taken away" do
      store = Fixtures.graphical_store
      shot = Picture.new Fixtures.pixels, columns: 4, rows: 2
      Fixtures.painted shot, 30, 8, images: store

      shot.pixels = nil
      Fixtures.painted shot, 30, 8, images: store

      expect(shot.image).to be_nil
      expect(store.placements).to be_empty
      expect(store.images).to be_empty
    end
  end

  # One image showing a different rectangle of itself in each of several places.
  describe "#crop" do
    it "asks for the part of the picture it was given" do
      store = Fixtures.graphical_store
      shot = Picture.new Fixtures.sheet, columns: 4, rows: 2,
        crop: Rect.new(0, 0, 4, 4)
      Fixtures.painted shot, 30, 8, images: store

      expect(store.placements.first.crop).to eq Rect.new(0, 0, 4, 4)
      expect(Fixtures.sequences(store).first).to contain "x=0,y=0,w=4,h=4,"
    end

    it "steps to another part without sending the pixels again" do
      store = Fixtures.graphical_store
      shot = Picture.new Fixtures.sheet, columns: 4, rows: 2,
        crop: Rect.new(0, 0, 4, 4)
      Fixtures.painted shot, 30, 8, images: store
      store.take_pending

      shot.crop = Rect.new(4, 4, 4, 4)
      Fixtures.painted shot, 30, 8, images: store

      sent = Fixtures.sequences store
      expect(sent.count(&.includes? "a=T")).to eq 0
      expect(sent.count(&.includes? "x=4,y=4,w=4,h=4,")).to eq 1
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
