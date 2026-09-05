require "../../spec_helper"
require "./overlay_harness_spec"

Spectator.describe TermBuf::Widgets::Toasts do
  alias Toasts = TermBuf::Widgets::Toasts
  alias Toast = TermBuf::Widgets::Toast
  alias Point = Layout::AttachPoint

  # A screen, a stack of toasts in one of its corners, and a clock nothing
  # waits on.
  def staged(corner : Point = Point::RightBottom,
             max_visible : Int32 = 3) : {Fixtures::Ground, Toasts, Fixtures::Ground::Clock}
    ground = Fixtures::Ground.new
    clock = Fixtures::Ground::Clock.new
    clock.install ground.app
    toasts = Toasts.new ground.app, corner: corner, max_visible: max_visible
    {ground, toasts, clock}
  end

  describe "the stack" do
    it "puts the newest nearest a bottom corner" do
      ground, toasts, _clock = staged
      first = toasts.show "one"
      second = toasts.show "two"
      ground.app.frame

      expect(toasts.container.children).to eq [first, second] of TermBuf::Widgets::Widget
      expect(second.rect.y).to be > first.rect.y
    end

    it "puts the newest nearest a top corner" do
      ground, toasts, _clock = staged corner: Point::RightTop
      first = toasts.show "one"
      second = toasts.show "two"
      ground.app.frame

      expect(toasts.container.children).to eq [second, first] of TermBuf::Widgets::Widget
      expect(second.rect.y).to be < first.rect.y
    end

    it "pushes the oldest off past the count it shows" do
      ground, toasts, _clock = staged max_visible: 2
      first = toasts.show "one"
      toasts.show "two"
      toasts.show "three"
      ground.app.frame

      expect(toasts.toasts.map &.text).to eq %w[two three]
      expect(first.parent).to be_nil
      expect(ground.of(Toast::Dismissed).map &.toast).to eq [first]
    end

    it "draws what it says in the corner it was given" do
      ground, toasts, _clock = staged
      toasts.show "saved"
      lines = ground.lines

      expect(lines[10].ends_with?(" saved")).to be_true
    end

    it "draws nothing at all when there is nothing to say" do
      ground, _toasts, _clock = staged

      expect(ground.lines.all?(&.==("."))).to be_true
    end
  end

  describe "the clock" do
    it "arms a timer for each toast" do
      _ground, toasts, clock = staged
      toast = toasts.show "one", ttl: 2.seconds

      expect(clock.waiting.size).to eq 1
      expect(clock.armed.values).to eq [2.seconds]
      expect(toast.nonce).to eq clock.waiting.first
    end

    it "takes the toast down when the timer goes off" do
      ground, toasts, clock = staged
      toast = toasts.show "one", ttl: 2.seconds
      nonce = clock.waiting.first
      clock.fire ground.app, nonce

      expect(toasts.toasts).to be_empty
      expect(toast.parent).to be_nil
      expect(ground.of(Toast::Dismissed).map &.toast).to eq [toast]
    end

    it "arms nothing for a toast that was given no life" do
      _ground, toasts, clock = staged
      toasts.show "one", ttl: nil

      expect(clock.waiting).to be_empty
    end

    it "withdraws the timer of a toast taken down early" do
      _ground, toasts, clock = staged
      toast = toasts.show "one", ttl: 2.seconds
      nonce = clock.waiting.first
      toasts.dismiss toast

      expect(clock.cancelled).to eq [nonce]
      expect(clock.waiting).to be_empty
    end

    it "leaves a toast up where nothing wired a clock in" do
      ground = Fixtures::Ground.new
      toasts = Toasts.new ground.app
      toast = toasts.show "one", ttl: 2.seconds

      expect(toast.nonce).to be_nil
      expect(toasts.toasts).to eq [toast]
    end
  end

  describe "dismissing" do
    it "goes away when it is clicked" do
      ground, toasts, _clock = staged
      toast = toasts.show "saved"
      ground.app.frame
      spot = toast.rect
      ground.press_at spot.x + 1, spot.y

      expect(toasts.toasts).to be_empty
      expect(ground.of(Toast::Dismissed).map &.toast).to eq [toast]
    end

    it "leaves a click somewhere else to whatever is under it" do
      ground, toasts, _clock = staged
      toasts.show "saved"
      ground.under.seen.clear
      ground.press_at 0, 0

      expect(toasts.toasts.size).to eq 1
      expect(ground.under.seen).not_to be_empty
    end

    it "says nothing for a toast that has already gone" do
      ground, toasts, _clock = staged
      toast = toasts.show "one"
      toasts.dismiss toast

      expect(toasts.dismiss(toast)).to be_false
      expect(ground.of(Toast::Dismissed).size).to eq 1
    end

    it "takes them all down at once without saying anything" do
      ground, toasts, clock = staged
      toasts.show "one"
      toasts.show "two"
      toasts.clear

      expect(toasts.toasts).to be_empty
      expect(clock.waiting).to be_empty
      expect(ground.of(Toast::Dismissed)).to be_empty
    end
  end
end
