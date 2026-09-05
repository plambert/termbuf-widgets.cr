require "../../spec_helper"
require "../overlay/overlay_harness_spec"

Spectator.describe TermBuf::Widgets::Hyperlink do
  alias Hyperlink = TermBuf::Widgets::Hyperlink
  alias Reveal = TermBuf::Widgets::Hyperlink::Reveal

  # A screen, a log at the root, a link on it, and a note of everything the
  # application was asked to copy.
  #
  # Something else focusable sits under the link, because the keyboard lands on
  # the first focusable widget of a fresh ring and half of what is being
  # checked here is what a link looks like before it is tabbed to.
  class Staged
    getter root : Fixtures::MessageLog
    getter link : Hyperlink
    getter app : Fixtures::TestApp
    getter elsewhere : Fixtures::Box
    getter copied = [] of String

    def initialize(@link : Hyperlink, columns : Int32 = 30, rows : Int32 = 6,
                   clipboard : Bool = true)
      @root = Fixtures::MessageLog.new width: Layout::Sizing.grow,
        height: Layout::Sizing.grow
      @elsewhere = Fixtures::Box.new
      @elsewhere.focusable = true
      @root.add @elsewhere, @link

      @app = Fixtures::TestApp.new @root, columns, rows
      @app.copy = ->(text : String) { @copied << text; nil } if clipboard
      @link.attach @app
      @app.frame
    end

    # Puts the keyboard on the link and takes a frame.
    def focus : Nil
      @app.focus.focus @link
      @app.frame
    end

    # Sends *keys* and lets everything they caused be delivered.
    def press(keys : String) : Nil
      @app.frame
      Fixtures.presses @app, keys
      @app.frame
    end

    # Clicks at (*x*, *y*).
    def click(x : Int32, y : Int32) : Nil
      @app.frame
      Fixtures.click @app, x, y
      @app.frame
    end

    # The messages of one kind that reached the root.
    def of(kind : Klass.class) : Array(Klass) forall Klass
      Fixtures.settle @app
      @root.of kind
    end

    # What the screen shows.
    def lines : Array(String)
      @app.frame
      @app.lines
    end

    # The URL the cell at (*x*, *y*) carries, or `nil` when it carries none.
    def uri_at(x : Int32, y : Int32) : String?
      @app.frame
      buffer = @app.buffer
      buffer.links[Fixtures.style_at(buffer, x, y).link]?.try &.uri
    end
  end

  def staged(link : Hyperlink, **options) : Staged
    Staged.new link, **options
  end

  describe "the link on the cells" do
    it "carries the URL on every cell of the text" do
      stage = staged Hyperlink.new("example", "https://example.com")

      expect(stage.uri_at(0, 0)).to eq "https://example.com"
      expect(stage.uri_at(6, 0)).to eq "https://example.com"
    end

    it "carries nothing at all for a link pointing nowhere" do
      stage = staged Hyperlink.new("example")

      expect(stage.uri_at(0, 0)).to be_nil
    end

    it "underlines the text" do
      stage = staged Hyperlink.new("example", "https://example.com")
      stage.app.frame

      expect(Fixtures.style_at(stage.app.buffer, 0, 0).underline.single?).to be_true
    end
  end

  describe "the reveal" do
    it "puts the URL under the text once the keyboard is on it" do
      stage = staged Hyperlink.new("example", "https://example.com")
      expect(stage.lines[1]).to be_empty

      stage.focus
      expect(stage.lines[1]).to eq "https://example.com"
    end

    it "keeps the second row reserved whether or not it is showing" do
      link = Hyperlink.new "example", "https://example.com"
      stage = staged link
      was = link.rect

      stage.focus
      expect(link.rect).to eq was
      expect(link.rect.height).to eq 2
    end

    it "puts it after the text when it was asked for a suffix" do
      link = Hyperlink.new "example", "https://example.com", reveal: Reveal::Suffix
      stage = staged link

      expect(stage.lines.first).to eq "example"
      stage.focus
      expect(stage.lines.first).to eq "example https://example.com"
      expect(link.rect.height).to eq 1
    end

    it "shows nothing extra when it was asked for none" do
      link = Hyperlink.new "example", "https://example.com", reveal: Reveal::None
      stage = staged link
      stage.focus

      expect(stage.lines.first).to eq "example"
      expect(stage.lines[1]).to be_empty
      expect(link.rect.height).to eq 1
    end

    it "shows it for a link that was chosen rather than focused" do
      link = Hyperlink.new "example", "https://example.com"
      link.selected = true
      stage = staged link

      expect(stage.lines[1]).to eq "https://example.com"
    end
  end

  describe "following it" do
    it "says so on Enter" do
      link = Hyperlink.new "example", "https://example.com"
      stage = staged link
      stage.focus
      stage.press "Enter"

      said = stage.of Hyperlink::Activated
      expect(said.map &.url).to eq ["https://example.com"]
      expect(said.first.link).to be link
    end

    it "says so on a click, and takes the keyboard with it" do
      link = Hyperlink.new "example", "https://example.com"
      stage = staged link
      stage.click 2, 0

      expect(stage.of(Hyperlink::Activated).size).to eq 1
      expect(stage.app.focused).to be link
    end

    it "says nothing for a link pointing nowhere" do
      stage = staged Hyperlink.new("example")
      stage.focus
      stage.press "Enter"

      expect(stage.of(Hyperlink::Activated)).to be_empty
    end
  end

  describe "copying it" do
    it "puts the URL on the clipboard on the copy key" do
      stage = staged Hyperlink.new("example", "https://example.com")
      stage.focus
      stage.press "c"

      expect(stage.copied).to eq ["https://example.com"]
      expect(stage.of(Hyperlink::Copied).map &.url).to eq ["https://example.com"]
    end

    it "takes a different key when it was given one" do
      link = Hyperlink.new "example", "https://example.com",
        copy_key: TermBuf::Key.parse("y").first
      stage = staged link
      stage.focus
      stage.press "c"
      expect(stage.copied).to be_empty

      stage.press "y"
      expect(stage.copied).to eq ["https://example.com"]
    end

    it "copies nothing where the application has no clipboard" do
      stage = staged Hyperlink.new("example", "https://example.com"), clipboard: false
      stage.focus
      stage.press "c"

      expect(stage.copied).to be_empty
      expect(stage.of(Hyperlink::Copied)).to be_empty
    end

    it "knows whether there is anywhere for a copy to go" do
      link = Hyperlink.new "example", "https://example.com"
      staged link
      expect(link.copiable?).to be_true

      other = Hyperlink.new "example", "https://example.com"
      staged other, clipboard: false
      expect(other.copiable?).to be_false
    end
  end
end
