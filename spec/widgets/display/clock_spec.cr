require "../../spec_helper"
require "../overlay/overlay_harness_spec"

# The moment a spec is looking at, so that moving time on is a matter of
# writing to it and the widget reading it again.
class ClockHands
  property at : Time

  def initialize(@at : Time)
  end

  # A block answering whatever the moment is now, which is what a time widget
  # takes in place of `Time.local`.
  def reader : Proc(Time)
    -> { @at }
  end
end

Spectator.describe TermBuf::Widgets::Clock do
  alias Clock = TermBuf::Widgets::Clock

  def hands(hour : Int32 = 20, minute : Int32 = 40, second : Int32 = 49,
            nanosecond : Int32 = 0) : ClockHands
    ClockHands.new Time.local(2026, 9, 4, hour, minute, second, nanosecond: nanosecond,
      location: Time::Location::UTC)
  end

  # A clock in an application, with a timer nothing waits on.
  def staged(clock : Clock) : {Fixtures::TestApp, Fixtures::Ground::Clock}
    root = TermBuf::Widgets::Panel.new width: Layout::Sizing.grow,
      height: Layout::Sizing.grow
    root.add clock

    app = Fixtures::TestApp.new root, 24, 3
    timer = Fixtures::Ground::Clock.new
    timer.install app
    app.frame

    {app, timer}
  end

  describe "#text" do
    it "writes the time the way it was told to" do
      moment = hands
      expect(Clock.new(now: moment.reader).text).to eq "20:40:49"
      expect(Clock.new("%H:%M", now: moment.reader).text).to eq "20:40"
      expect(Clock.new("%I:%M %p", now: moment.reader).text).to eq "08:40 pm"
    end

    it "takes a fresh reading when the format changes" do
      clock = Clock.new now: hands.reader
      clock.format = "%H:%M"

      expect(clock.text).to eq "20:40"
    end

    it "stays on the reading it took until something refreshes it" do
      moment = hands
      clock = Clock.new now: moment.reader
      moment.at += 1.hour

      expect(clock.text).to eq "20:40:49"
      clock.refresh
      expect(clock.text).to eq "21:40:49"
    end
  end

  describe "#draw" do
    it "puts the reading on the screen" do
      clock = Clock.new now: hands.reader

      expect(Fixtures.render(clock, 12, 1).first).to eq "20:40:49"
    end

    it "puts it where the alignment asks for" do
      clock = Clock.new now: hands.reader, align: TermBuf::Unicode::Align::Right
      clock.width = Layout::Sizing.fixed 12

      expect(Fixtures.render(clock, 12, 1).first).to eq "    20:40:49"
    end
  end

  describe "#interval" do
    it "waits out what is left of the second" do
      clock = Clock.new now: hands(nanosecond: 250_000_000).reader

      expect(clock.interval).to eq 750.milliseconds
    end

    it "waits a whole second from a whole second" do
      clock = Clock.new now: hands.reader

      expect(clock.interval).to eq 1.second
    end

    it "waits out what is left of a coarser resolution" do
      clock = Clock.new "%H:%M", resolution: 1.minute, now: hands.reader

      expect(clock.interval).to eq 11.seconds
    end
  end

  describe "the timer" do
    it "arms one for the next boundary when it is started" do
      moment = hands nanosecond: 250_000_000
      clock = Clock.new now: moment.reader
      app, timer = staged clock
      clock.start app

      expect(timer.armed.values).to eq [750.milliseconds]
    end

    it "takes a fresh reading and arms the next when it goes off" do
      moment = hands
      clock = Clock.new now: moment.reader
      app, timer = staged clock
      clock.start app
      moment.at += 1.second
      timer.fire app, timer.waiting.first

      expect(clock.text).to eq "20:40:50"
      expect(timer.waiting.size).to eq 1
    end

    it "lays the tree out again for a reading of a different width" do
      moment = hands hour: 23, minute: 59, second: 59
      clock = Clock.new "%A", now: moment.reader
      app, timer = staged clock
      clock.start app
      app.frame
      was = clock.rect.width

      moment.at += 1.second
      timer.fire app, timer.waiting.first
      app.frame

      expect(clock.text).to eq moment.at.to_s("%A")
      expect(clock.rect.width).to eq clock.text.size
      expect(clock.rect.width).not_to eq was
    end

    it "withdraws the timer when it is stopped" do
      clock = Clock.new now: hands.reader
      app, timer = staged clock
      clock.start app
      nonce = timer.waiting.first
      clock.stop

      expect(timer.cancelled).to eq [nonce]
      expect(clock.running?).to be_false
    end
  end
end
