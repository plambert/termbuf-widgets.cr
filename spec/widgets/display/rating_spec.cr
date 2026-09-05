require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Rating do
  alias Rating = TermBuf::Widgets::Rating
  alias Glyphs = TermBuf::Widgets::Rating::Glyphs
  alias Router = TermBuf::Widgets::Router
  alias Focus = TermBuf::Widgets::Focus
  alias Style = TermBuf::Style

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }
  let(cjk) { TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2 }

  # A rating drawn in ASCII, which is what the drawing cases read back.
  def ascii(value : Number = 0, **options) : Rating
    Rating.new value, **options, glyphs: Glyphs::ASCII
  end

  # A laid-out tree with a router over it, and the rating focused.
  def wired(stars : Rating) : Router
    root = Fixtures::Box.new
    root.add stars
    tree = Layout::Tree.new root, Rect.full(20, 4)
    tree.layout

    focus = Focus::Stack.new root
    router = Router.new tree, focus
    focus.focus stars
    router
  end

  def press(router : Router, name : TermBuf::Key::Name) : Nil
    router.dispatch TermBuf::Events::Key.new(TermBuf::Key.named(name), Bytes.empty)
  end

  def type(router : Router, char : Char) : Nil
    router.dispatch TermBuf::Events::Key.new(TermBuf::Key.character(char), Bytes.empty)
  end

  def click(router : Router, x : Int32, y : Int32) : Bool
    router.dispatch TermBuf::Events::Mouse.new(
      TermBuf::Input::Mouse::Button::Left, x, y,
      TermBuf::Modifiers::None, TermBuf::Input::Mouse::Action::Press)
  end

  describe "Glyphs" do
    it "takes the stars when every one of them is a single cell" do
      expect(Glyphs.for(policy)).to eq Glyphs::UNICODE
    end

    it "falls back to ASCII when the policy would draw a star two cells wide" do
      expect(Glyphs.for(cjk)).to eq Glyphs::ASCII
    end

    it "measures its widest character" do
      expect(Glyphs::UNICODE.width(policy)).to eq 1
      expect(Glyphs::UNICODE.width(cjk)).to eq 2
    end
  end

  describe "#value=" do
    it "holds the value between zero and the maximum" do
      stars = Rating.new

      stars.value = 9
      expect(stars.value).to eq 5.0

      stars.value = -1
      expect(stars.value).to eq 0.0
    end

    it "leaves the tree alone, because no geometry comes of it" do
      stars = Rating.new 1
      tree = Layout::Tree.new stars, Rect.full(20, 3)
      tree.layout_if_needed

      stars.value = 4
      expect(tree.dirty?).to be_false
    end
  end

  describe "#max=" do
    it "brings a value above the new maximum back inside it" do
      stars = Rating.new 5
      stars.max = 3

      expect(stars.value).to eq 3.0
    end

    it "marks the tree dirty, because the row got shorter" do
      stars = Rating.new 5
      tree = Layout::Tree.new stars, Rect.full(20, 3)
      tree.layout_if_needed

      stars.max = 3
      expect(tree.dirty?).to be_true
    end

    it "will not take a maximum below one" do
      expect { Rating.new max: 0 }.to raise_error(ArgumentError, /max/)
    end
  end

  describe "#draw" do
    it "draws a full star for each whole one earned" do
      expect(Fixtures.render(ascii(3), 10, 1)).to eq ["***--"]
    end

    it "draws a half star for the half" do
      expect(Fixtures.render(ascii(3.5), 10, 1)).to eq ["***+-"]
    end

    it "draws every star empty at zero" do
      expect(Fixtures.render(ascii(0), 10, 1)).to eq ["-----"]
    end

    it "draws every star full at the maximum" do
      expect(Fixtures.render(ascii(5), 10, 1)).to eq ["*****"]
    end

    it "draws as many stars as it was told to" do
      expect(Fixtures.render(ascii(2, max: 3), 10, 1)).to eq ["**-"]
    end

    it "leaves the spacing it was given between the stars" do
      expect(Fixtures.render(ascii(2, max: 3, spacing: 1), 10, 1)).to eq ["* * -"]
    end

    it "draws the stars when the policy can carry them" do
      expect(Fixtures.render(Rating.new(1.5, max: 3), 10, 1)).to eq ["★⯪☆"]
    end

    it "falls back to ASCII under a policy that would draw them ragged" do
      expect(Fixtures.render(Rating.new(1.5, max: 3), 10, 1, cjk)).to eq ["*+-"]
    end

    it "draws an earned star and an empty one in different styles" do
      stars = ascii 1, max: 2
      stars.filled_style = Style::DEFAULT.bold
      painted = Fixtures.painted stars, 10, 1

      expect(Fixtures.style_at(painted, 0, 0).has?(TermBuf::Attributes::Bold)).to be_true
      expect(Fixtures.style_at(painted, 1, 0).has?(TermBuf::Attributes::Faint)).to be_true
    end

    it "stops at the edge of a box too narrow for every star" do
      expect(Fixtures.render(ascii(5), 3, 1)).to eq ["***"]
    end
  end

  describe "#intrinsic_width" do
    it "wants a cell per star" do
      expect(ascii(0, max: 4).intrinsic_width(policy).preferred).to eq 4
    end

    it "counts the spacing between them" do
      expect(ascii(0, max: 4, spacing: 1).intrinsic_width(policy).preferred).to eq 7
    end

    it "counts two cells a star under a policy that draws them that wide" do
      expect(Rating.new(0, max: 3, glyphs: Glyphs::UNICODE).intrinsic_width(cjk).preferred).to eq 6
    end
  end

  describe "read-only by default" do
    it "does not take focus" do
      expect(Rating.new.focusable?).to be_false
    end

    it "binds no keys" do
      expect(Rating.new.keymap).to be_nil
    end

    it "ignores a click" do
      stars = Rating.new 2
      router = wired stars
      click router, 0, 0

      expect(stars.value).to eq 2.0
    end
  end

  describe "editable" do
    it "takes focus and binds keys" do
      stars = Rating.new editable: true

      expect(stars.focusable?).to be_true
      expect(stars.keymap).not_to be_nil
    end

    it "unbinds them again when it stops being editable" do
      stars = Rating.new editable: true
      stars.editable = false

      expect(stars.keymap).to be_nil
    end

    it "steps up on Right and down on Left" do
      stars = Rating.new 2, editable: true
      router = wired stars

      press router, TermBuf::Key::Name::Right
      expect(stars.value).to eq 3.0

      press router, TermBuf::Key::Name::Left
      expect(stars.value).to eq 2.0
    end

    it "steps by the amount it was told to" do
      stars = Rating.new 2, editable: true, step: 0.5
      router = wired stars

      press router, TermBuf::Key::Name::Right
      expect(stars.value).to eq 2.5
    end

    it "stops at the ends rather than running past them" do
      stars = Rating.new 5, editable: true
      router = wired stars

      press router, TermBuf::Key::Name::Right
      expect(stars.value).to eq 5.0
    end

    it "goes to no stars on Home and every star on End" do
      stars = Rating.new 2, editable: true
      router = wired stars

      press router, TermBuf::Key::Name::End
      expect(stars.value).to eq 5.0

      press router, TermBuf::Key::Name::Home
      expect(stars.value).to eq 0.0
    end

    it "takes a digit as that many stars" do
      stars = Rating.new 0, editable: true
      router = wired stars

      type router, '3'
      expect(stars.value).to eq 3.0
    end

    it "holds a digit above the maximum down to it" do
      stars = Rating.new 0, max: 3, editable: true
      router = wired stars

      type router, '9'
      expect(stars.value).to eq 3.0
    end

    it "sets the value to the star that was clicked" do
      stars = Rating.new 0, editable: true
      router = wired stars

      expect(click(router, 2, 0)).to be_true
      expect(stars.value).to eq 3.0
    end

    it "takes the click at the left edge as one star" do
      stars = Rating.new 5, editable: true
      router = wired stars
      click router, 0, 0

      expect(stars.value).to eq 1.0
    end

    it "ignores a click in the gap between two stars" do
      stars = Rating.new 1, editable: true, spacing: 1
      router = wired stars
      click router, 1, 0

      expect(stars.value).to eq 1.0
    end

    it "says the value changed" do
      stars = Rating.new 0, editable: true
      router = wired stars
      seen = [] of TermBuf::Widgets::Message

      root = stars.parent.as(Fixtures::Box)
      root.on_handle = ->(event : TermBuf::Event, _context : TermBuf::Widgets::Context) do
        seen << event if event.is_a? TermBuf::Widgets::Message
        nil
      end

      press router, TermBuf::Key::Name::Right
      router.drain

      expect(seen.size).to eq 1
      expect(seen.first.as(Rating::Changed).value).to eq 1.0
    end

    it "says nothing when the value did not move" do
      stars = Rating.new 5, editable: true
      router = wired stars

      press router, TermBuf::Key::Name::Right
      expect(router.pending).to be_empty
    end
  end

  describe "in a layout" do
    it "fits the row of stars" do
      root = TermBuf::Widgets::Panel.new width: Sizing.grow, height: Sizing.grow
      stars = ascii 3, max: 4
      root.add stars

      Layout::Tree.new(root, Rect.full(20, 4)).layout

      expect(stars.rect.width).to eq 4
      expect(stars.rect.height).to eq 1
    end
  end
end
