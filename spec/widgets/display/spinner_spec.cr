require "../../spec_helper"
require "../overlay/overlay_harness_spec"

Spectator.describe TermBuf::Widgets::Spinner do
  alias Spinner = TermBuf::Widgets::Spinner
  alias Frames = TermBuf::Widgets::Spinner::Frames

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }
  let(cjk) { TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2 }

  # A spinner in an application, with a clock nothing waits on.
  def staged(spinner : Spinner) : {Fixtures::TestApp, Fixtures::Ground::Clock}
    root = TermBuf::Widgets::Panel.new width: Layout::Sizing.grow,
      height: Layout::Sizing.grow
    root.add spinner

    app = Fixtures::TestApp.new root, 24, 3
    clock = Fixtures::Ground::Clock.new
    clock.install app
    app.frame

    {app, clock}
  end

  describe "Frames" do
    it "refuses a set with nothing in it" do
      expect { Frames.new %w[] }.to raise_error ArgumentError
    end

    it "counts round the set" do
      expect(Frames::ASCII[0]).to eq "|"
      expect(Frames::ASCII[4]).to eq "|"
      expect(Frames::ASCII[-1]).to eq "\\"
    end

    it "measures its widest frame" do
      expect(Frames::BAR.width(policy)).to eq 1
      expect(Frames::BAR.width(cjk)).to eq 2
    end

    it "knows the braille dots survive a policy the blocks do not" do
      expect(Frames::BRAILLE.single_cell?(cjk)).to be_true
      expect(Frames::BAR.single_cell?(cjk)).to be_false
      expect(Frames::MOON.single_cell?(cjk)).to be_false
    end
  end

  describe "the set it draws" do
    it "takes the set it was given when the policy allows it" do
      spinner = Spinner.new frames: Frames::BAR
      expect(spinner.frames_for(policy)).to eq Frames::BAR
    end

    it "falls back where the set would not come out at a cell each" do
      spinner = Spinner.new frames: Frames::BAR
      expect(spinner.frames_for(cjk)).to eq Frames::ASCII
    end

    it "keeps a set that names itself as its own fallback" do
      spinner = Spinner.new frames: Frames::BAR, fallback: Frames::BAR
      expect(spinner.frames_for(cjk)).to eq Frames::BAR
    end
  end

  describe "#draw" do
    it "puts the frame that is up on the screen" do
      spinner = Spinner.new frames: Frames::ASCII
      expect(Fixtures.render(spinner, 8, 1).first).to eq "|"

      spinner.advance
      expect(Fixtures.render(spinner, 8, 1).first).to eq "/"
    end

    it "writes the text after the frame" do
      spinner = Spinner.new "loading", frames: Frames::ASCII
      expect(Fixtures.render(spinner, 12, 1).first).to eq "| loading"
    end

    it "pads a narrow frame out to the widest of the set" do
      wide = Frames.new ["ab", "c"]
      spinner = Spinner.new "x", frames: wide, fallback: wide
      spinner.index = 1

      expect(Fixtures.render(spinner, 12, 1).first).to eq "c  x"
    end
  end

  describe "the width" do
    it "stays put as the frames go by" do
      spinner = Spinner.new "loading", frames: Frames::ASCII
      app, _clock = staged spinner
      was = spinner.rect

      4.times do
        spinner.advance
        app.frame
      end

      expect(spinner.rect).to eq was
    end

    it "reserves the widest frame in the set" do
      wide = Frames.new ["ab", "c"]
      spinner = Spinner.new frames: wide, fallback: wide

      expect(spinner.intrinsic_width(policy).preferred).to eq 2
    end
  end

  describe "the clock" do
    it "arms nothing until it is started" do
      spinner = Spinner.new frames: Frames::ASCII
      _app, clock = staged spinner

      expect(clock.waiting).to be_empty
      expect(spinner.running?).to be_false
    end

    it "arms a timer for its interval" do
      spinner = Spinner.new frames: Frames::ASCII, interval: 50.milliseconds
      app, clock = staged spinner
      spinner.start app

      expect(clock.armed.values).to eq [50.milliseconds]
      expect(spinner.running?).to be_true
    end

    it "moves on a frame and arms the next when the timer goes off" do
      spinner = Spinner.new frames: Frames::ASCII
      app, clock = staged spinner
      spinner.start app
      clock.fire app, clock.waiting.first

      expect(spinner.index).to eq 1
      expect(spinner.running?).to be_true
      expect(clock.waiting.size).to eq 1
    end

    it "keeps going round the set" do
      spinner = Spinner.new frames: Frames::ASCII
      app, clock = staged spinner
      spinner.start app
      4.times { clock.fire app, clock.waiting.first }

      expect(spinner.index).to eq 0
    end

    it "withdraws the timer when it is stopped" do
      spinner = Spinner.new frames: Frames::ASCII
      app, clock = staged spinner
      spinner.start app
      nonce = clock.waiting.first
      spinner.stop

      expect(clock.cancelled).to eq [nonce]
      expect(clock.waiting).to be_empty
      expect(spinner.running?).to be_false
    end

    it "stays on its first frame where nothing wired a clock in" do
      spinner = Spinner.new frames: Frames::ASCII
      root = TermBuf::Widgets::Panel.new
      root.add spinner
      app = Fixtures::TestApp.new root, 24, 3
      spinner.start app

      expect(spinner.running?).to be_false
      expect(spinner.index).to eq 0
    end
  end
end
