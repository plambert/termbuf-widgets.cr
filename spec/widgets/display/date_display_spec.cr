require "../../spec_helper"

Spectator.describe TermBuf::Widgets::DateDisplay do
  alias DateDisplay = TermBuf::Widgets::DateDisplay

  let(at) { Time.local 2026, 9, 4, 20, 40, 49, location: Time::Location::UTC }

  # A root for *stamp* to be laid out inside, since a tree's own root is given
  # the whole screen whatever it asked for.
  def boxed(stamp : DateDisplay) : TermBuf::Widgets::Panel
    root = TermBuf::Widgets::Panel.new width: Layout::Sizing.grow,
      height: Layout::Sizing.grow
    root.add stamp
    root
  end

  describe "#text" do
    it "writes the date the way it was told to" do
      table = {
        "%Y-%m-%d"       => "2026-09-04",
        "%d/%m/%Y"       => "04/09/2026",
        "%Y-%m-%d %H:%M" => "2026-09-04 20:40",
        "%B %d, %Y"      => "September 04, 2026",
      }

      table.each do |format, said|
        expect(DateDisplay.new(at, format).text).to eq said
      end
    end

    it "takes the plain date when nothing says otherwise" do
      expect(DateDisplay.new(at).text).to eq "2026-09-04"
    end
  end

  describe "#draw" do
    it "puts the date on the screen" do
      expect(Fixtures.render(DateDisplay.new(at), 20, 1).first).to eq "2026-09-04"
    end

    it "cuts a date wider than the box it was given" do
      stamp = DateDisplay.new at, "%Y-%m-%d %H:%M:%S"
      stamp.width = Layout::Sizing.fixed 8

      expect(Fixtures.render(boxed(stamp), 20, 1).first).to eq "2026-09…"
    end

    it "puts it where the alignment asks for" do
      stamp = DateDisplay.new at, align: TermBuf::Unicode::Align::Right
      stamp.width = Layout::Sizing.fixed 14

      expect(Fixtures.render(stamp, 14, 1).first).to eq "    2026-09-04"
    end
  end

  describe "the layout" do
    it "asks for the room the date needs, and says so when that changes" do
      stamp = DateDisplay.new at
      root = boxed stamp
      Fixtures.painted root, 20, 1
      expect(stamp.rect.width).to eq 10

      stamp.format = "%Y-%m-%d %H:%M"
      Fixtures.painted root, 20, 1
      expect(stamp.rect.width).to eq 16
    end
  end
end
