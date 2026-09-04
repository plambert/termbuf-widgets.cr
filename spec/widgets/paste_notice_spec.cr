require "../spec_helper"

Spectator.describe TermBuf::Widgets::PasteNotice do
  alias Box = Fixtures::Box
  alias PasteNotice = TermBuf::Widgets::PasteNotice

  # A screen with *notice* floating over a background of dots.
  def over(notice : PasteNotice, columns : Int32, rows : Int32) : Array(String)
    root = Box.new
    root.add TermBuf::Widgets::Label.new(("." * columns + "\n") * rows, wrap: Layout::Wrap::None)
    root.add notice

    Fixtures.render root, columns, rows
  end

  it "draws nothing at all while nothing is arriving" do
    notice = PasteNotice.new

    expect(notice.hidden?).to be_true
    expect(over(notice, 20, 5).join).not_to contain "pasting"
  end

  it "says how much has arrived, in the middle of the screen" do
    notice = PasteNotice.new
    notice.arriving 4096

    lines = over notice, 30, 5
    expect(lines.join('\n')).to contain "pasting 4096 bytes"
    expect(lines[2]).to contain "pasting"
  end

  it "keeps a label too wide for the screen inside its own panel" do
    notice = PasteNotice.new label: "pasting a great deal of something"
    notice.arriving 4096

    lines = over notice, 12, 5
    lines.each { |line| expect(line.size).to be <= 12 }
  end

  it "goes away when the paste ends" do
    notice = PasteNotice.new
    notice.arriving 10
    expect(notice.visible?).to be_true
    expect(notice.hidden?).to be_false

    notice.finished
    expect(notice.visible?).to be_false
    expect(notice.hidden?).to be_true
  end

  describe "its size" do
    it "asks for the label and a little quiet either side" do
      notice = PasteNotice.new
      notice.arriving 4096

      root = Box.new
      root.add notice
      Layout::Tree.new(root, Rect.full(40, 9)).layout

      expect(notice.rect.width).to eq "pasting 4096 bytes".size + 4
      expect(notice.rect.height).to eq 3
    end

    it "asks for two more of each when it wears a border" do
      notice = PasteNotice.new border: TermBuf::Widgets::Border.plain
      notice.arriving 4096

      root = Box.new
      root.add notice
      Layout::Tree.new(root, Rect.full(40, 9)).layout

      expect(notice.rect.width).to eq "pasting 4096 bytes".size + 6
      expect(notice.rect.height).to eq 5
    end

    it "sits in the middle of the screen" do
      notice = PasteNotice.new label: "x"
      notice.arriving 1

      root = Box.new
      root.add notice
      Layout::Tree.new(root, Rect.full(41, 9)).layout

      expect(notice.rect).to eq Rect.new(14, 3, 13, 3)
    end

    it "grows as the paste does" do
      notice = PasteNotice.new
      notice.arriving 4
      root = Box.new
      root.add notice
      tree = Layout::Tree.new root, Rect.full(40, 9)
      tree.layout
      narrow = notice.rect.width

      notice.arriving 4_000_000
      tree.layout_if_needed

      expect(notice.rect.width).to be > narrow
    end
  end
end
