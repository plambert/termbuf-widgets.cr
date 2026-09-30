require "./spec_helper"

Spectator.describe TermBuf::Widgets::Renderer do
  alias Box = Fixtures::Box
  alias Label = TermBuf::Widgets::Label
  alias Point = Layout::AttachPoint

  describe "a widget in a box" do
    it "draws the border and puts the content inside it" do
      root = Box.new
      root.border = TermBuf::Widgets::Border.plain
      root.add Label.new("hi")

      expect(Fixtures.render(root, 8, 3)).to eq ["┌──────┐", "│hi    │", "└──────┘"]
    end

    it "puts a title in the top edge" do
      root = Box.new
      root.border = TermBuf::Widgets::Border.rounded title: "name"
      root.add Label.new("hi")

      expect(Fixtures.render(root, 12, 3).first).to eq "╭─name─────╮"
    end

    it "wraps the content to what the border left it" do
      root = Box.new
      root.border = TermBuf::Widgets::Border.plain
      root.add Label.new("one two")

      expect(Fixtures.render(root, 7, 4)).to eq ["┌─────┐", "│one  │", "│two  │", "└─────┘"]
    end
  end

  describe "a scroll panel" do
    def scrolled(scroll : Int32) : Array(String)
      root = Box.new
      panel = Box.new
      panel.clip_y = true
      panel.scroll_y = scroll
      panel.height = Sizing.fixed 2
      panel.add Label.new("one"), Label.new("two"), Label.new("three")
      root.add panel, Label.new("out")

      Fixtures.render root, 6, 4
    end

    it "shows the rows the scroll brought into view" do
      expect(scrolled(1)).to eq ["two", "three", "out", ""]
    end

    it "shows the first rows when nothing is scrolled" do
      expect(scrolled(0)).to eq ["one", "two", "out", ""]
    end

    it "cuts what runs past its own edge rather than the screen's" do
      root = Box.new
      panel = Box.new
      panel.clip_x = true
      panel.scroll_x = 2
      panel.width = Sizing.fixed 4
      panel.direction = Layout::Direction::Row
      inner = Label.new "abcdefgh", wrap: Layout::Wrap::None
      inner.width = Sizing.fixed 8
      panel.add inner
      root.direction = Layout::Direction::Row
      root.add panel, Label.new("Z")

      expect(Fixtures.render(root, 6, 1)).to eq ["cdefZ"]
    end
  end

  describe "a float" do
    it "is drawn over the content it covers" do
      root = Box.new
      root.add Label.new("aaaaa")

      over = Label.new "XY"
      over.floating = Layout::Floating.on nil, Point::LeftTop, Point::LeftTop, dx: 1
      root.add over

      expect(Fixtures.render(root, 5, 1)).to eq ["aXYaa"]
    end

    it "is drawn in the order the painting order gives" do
      root = Box.new
      root.add Label.new("....")

      lower = Label.new "ab"
      lower.floating = Layout::Floating.on nil, Point::LeftTop, Point::LeftTop, z: 1
      upper = Label.new "Z"
      upper.floating = Layout::Floating.on nil, Point::LeftTop, Point::LeftTop, dx: 1, z: 2
      root.add lower, upper

      expect(Fixtures.render(root, 4, 1)).to eq ["aZ.."]
    end
  end

  describe "styles" do
    let(ground) { TermBuf::Style::DEFAULT.bg TermBuf::Color.indexed(4_u8) }

    it "reaches a child that never named one" do
      root = Box.new
      root.style = ground
      label = Label.new "hi"
      root.add label

      buffer = Fixtures.painted root, 4, 1
      expect(Fixtures.style_at(buffer, 0, 0).background).to eq ground.background
    end

    it "lets the child add to it without losing it" do
      root = Box.new
      root.style = ground
      label = Label.new "hi"
      label.style = TermBuf::Style::DEFAULT.bold
      root.add label

      painted = Fixtures.style_at Fixtures.painted(root, 4, 1), 0, 0
      expect(painted.background).to eq ground.background
      expect(painted.attributes.bold?).to be_true
    end

    it "paints the ground of a widget that named one, and no further" do
      root = Box.new
      root.direction = Layout::Direction::Row
      panel = Box.new
      panel.style = ground
      panel.width = Sizing.fixed 2
      panel.height = Sizing.fixed 1
      root.add panel, Box.sized(2, 1)

      buffer = Fixtures.painted root, 4, 1
      expect(Fixtures.style_at(buffer, 1, 0).background).to eq ground.background
      expect(Fixtures.style_at(buffer, 2, 0).background).to eq TermBuf::Style::DEFAULT.background
    end
  end

  describe "what it leaves alone" do
    it "draws nothing for a hidden widget" do
      root = Box.new
      shown = Label.new "aa"
      hidden = Label.new "bb"
      hidden.hidden = true
      root.add hidden, shown

      expect(Fixtures.render(root, 4, 2)).to eq ["aa", ""]
    end

    it "draws nothing outside the screen" do
      root = Box.new
      root.direction = Layout::Direction::Row
      wide = Label.new "abcdefgh", wrap: Layout::Wrap::None
      wide.width = Sizing.fixed 8
      root.add wide

      expect(Fixtures.render(root, 4, 1)).to eq ["abcd"]
    end
  end

  # A widget says every frame what it wants on screen, so the renderer has to
  # make saying it again free: a cover is a few hundred kilobytes and the wire
  # may be an ssh connection.
  describe "the pictures" do
    alias Picture = TermBuf::Widgets::Picture

    # A store over a terminal that draws pictures, so the bytes it would send
    # can be read.
    def graphical : TermBuf::ImageStore
      TermBuf::ImageStore.new TermBuf::Capabilities.new(TermBuf::Capability::KittyGraphics)
    end

    # Four red pixels, which is as small as a picture gets.
    def dots : TermBuf::Pixels
      TermBuf::Pixels.rgb Bytes[255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0], 2, 2
    end

    # The escape sequences one frame put on the wire.
    def sequences(store : TermBuf::ImageStore) : Array(String)
      store.take_pending.select &.starts_with? "\e_G"
    end

    it "sends the pixels on the frame that first wants them" do
      store = graphical
      Fixtures.render Picture.new(dots), 6, 2, images: store

      expect(sequences(store).count(&.includes? "a=T")).to eq 1
    end

    it "sends nothing for a frame that wants the same picture in the same box" do
      store = graphical
      shot = Picture.new dots
      Fixtures.render shot, 6, 2, images: store
      store.take_pending

      Fixtures.render shot, 6, 2, images: store

      expect(store.take_pending).to be_empty
      expect(store.placements.size).to eq 1
    end

    it "positions a picture whose box moved rather than sending it again" do
      store = graphical
      shot = Picture.new dots, columns: 2, rows: 1
      above = Box.new
      root = Box.new
      root.add above, shot

      Fixtures.render root, 6, 3, images: store
      expect(store.placements.first.bounds.y).to eq 0
      store.take_pending

      above.lines = 1
      Fixtures.render root, 6, 3, images: store

      sent = sequences store
      expect(sent.count(&.includes? "a=T")).to eq 0
      expect(sent.count(&.includes? "a=p")).to eq 1
      expect(store.placements.first.bounds.y).to eq 1
    end

    it "takes off a picture the widget stopped holding" do
      store = graphical
      shot = Picture.new dots
      Fixtures.render shot, 6, 2, images: store
      store.take_pending

      shot.pixels = nil
      Fixtures.render shot, 6, 2, images: store

      expect(sequences(store).join).to contain "a=d"
      expect(store.placements).to be_empty
      expect(store.images).to be_empty
    end

    it "sends nothing for a frame with no pictures in it" do
      store = graphical
      Fixtures.render Label.new("hi"), 6, 2, images: store

      expect(store.take_pending).to be_empty
    end

    # A picture an application put up itself is not the renderer's, and a frame
    # that never mentions it must leave it where it is. This is the background
    # behind a panel: put it up once and stop thinking about it.
    it "leaves a picture the application put up alone" do
      store = graphical
      behind = store.register(dots).show Rect.new(0, 0, 6, 2), z: -1
      store.take_pending

      Fixtures.render Label.new("hi"), 6, 2, images: store
      Fixtures.render Label.new("hi"), 6, 2, images: store

      expect(store.take_pending).to be_empty
      expect(behind.shown?).to be_true
      expect(store.placements).to eq [behind]
    end

    it "takes off its own picture and leaves the application's" do
      store = graphical
      behind = store.register(dots).show Rect.new(0, 0, 6, 2), z: -1
      shot = Picture.new dots
      Fixtures.render shot, 6, 2, images: store
      store.take_pending

      Fixtures.render Label.new("hi"), 6, 2, images: store

      expect(store.placements).to eq [behind]
      registered = shot.image
      fail "the widget registered nothing" unless registered
      expect(registered.forgotten?).to be_true
    end
  end
end
