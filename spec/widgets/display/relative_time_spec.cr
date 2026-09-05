require "../../spec_helper"
require "../overlay/overlay_harness_spec"
require "./clock_spec"

Spectator.describe TermBuf::Widgets::RelativeTime do
  alias RelativeTime = TermBuf::Widgets::RelativeTime

  # The moment every example here is measured from.
  def present : Time
    Time.local 2026, 9, 4, 12, 0, 0, location: Time::Location::UTC
  end

  # A widget describing a time *span* away from the present, ahead when *span*
  # is positive.
  def aged(span : Time::Span) : {RelativeTime, ClockHands}
    hands = ClockHands.new present
    {RelativeTime.new(present + span, now: hands.reader), hands}
  end

  # A widget in an application, with a timer nothing waits on.
  def staged(widget : RelativeTime) : {Fixtures::TestApp, Fixtures::Ground::Clock}
    root = TermBuf::Widgets::Panel.new width: Layout::Sizing.grow,
      height: Layout::Sizing.grow
    root.add widget

    app = Fixtures::TestApp.new root, 30, 3
    timer = Fixtures::Ground::Clock.new
    timer.install app
    app.frame

    {app, timer}
  end

  describe ".describe" do
    it "says just now for anything that has only just happened" do
      {0.seconds, 2.seconds, -4.seconds}.each do |span|
        expect(RelativeTime.describe(present + span, present)).to eq "just now"
      end
    end

    it "counts backwards in the unit that keeps the number small" do
      table = {
        30.seconds => "30 seconds ago",
        90.seconds => "1 minute ago",
        45.minutes => "45 minutes ago",
        3.hours    => "3 hours ago",
        30.hours   => "1 day ago",
        4.days     => "4 days ago",
        20.days    => "2 weeks ago",
        75.days    => "2 months ago",
        400.days   => "1 year ago",
        1200.days  => "3 years ago",
        1.hours    => "1 hour ago",
        7.days     => "1 week ago",
      }

      table.each do |span, said|
        expect(RelativeTime.describe(present - span, present)).to eq said
      end
    end

    it "counts forwards for a time that has not come yet" do
      expect(RelativeTime.describe(present + 30.seconds, present)).to eq "in 30 seconds"
      expect(RelativeTime.describe(present + 2.hours, present)).to eq "in 2 hours"
      expect(RelativeTime.describe(present + 400.days, present)).to eq "in 1 year"
    end

    it "takes the words for the recent past from the caller" do
      expect(RelativeTime.describe(present, present, "moments ago")).to eq "moments ago"
    end
  end

  describe "#text" do
    it "reads the way the description does" do
      widget, _hands = aged -3.minutes

      expect(widget.text).to eq "3 minutes ago"
    end

    it "takes a fresh reading when the time it describes changes" do
      widget, _hands = aged -3.minutes
      widget.at = present - 2.hours

      expect(widget.text).to eq "2 hours ago"
    end

    it "stays as it was until something refreshes it" do
      widget, hands = aged -30.seconds
      hands.at += 10.minutes

      expect(widget.text).to eq "30 seconds ago"
      widget.refresh
      expect(widget.text).to eq "10 minutes ago"
    end
  end

  describe "#draw" do
    it "puts what it says on the screen" do
      widget, _hands = aged -45.minutes

      expect(Fixtures.render(widget, 20, 1).first).to eq "45 minutes ago"
    end
  end

  describe "#interval" do
    it "slows down as the time it describes gets older" do
      table = {
        -30.seconds => 1.second,
        -30.minutes => 1.minute,
        -6.hours    => 1.hour,
        -9.days     => 1.day,
        30.minutes  => 1.minute,
      }

      table.each do |span, wanted|
        widget, _hands = aged span
        expect(widget.interval).to eq wanted
      end
    end
  end

  describe "the timer" do
    it "arms one for the refresh its age calls for" do
      widget, _hands = aged -30.minutes
      app, timer = staged widget
      widget.start app

      expect(timer.armed.values).to eq [1.minute]
    end

    it "takes a fresh reading and arms the next when it goes off" do
      widget, hands = aged -59.seconds
      app, timer = staged widget
      widget.start app
      hands.at += 1.second
      timer.fire app, timer.waiting.first

      expect(widget.text).to eq "1 minute ago"
      expect(timer.waiting.size).to eq 1
    end

    it "arms a longer one once the reading has aged past a unit" do
      widget, hands = aged -59.seconds
      app, timer = staged widget
      widget.start app
      hands.at += 1.second
      timer.fire app, timer.waiting.first

      expect(timer.armed.values).to eq [1.minute]
    end

    it "withdraws the timer when it is stopped" do
      widget, _hands = aged -30.minutes
      app, timer = staged widget
      widget.start app
      nonce = timer.waiting.first
      widget.stop

      expect(timer.cancelled).to eq [nonce]
      expect(widget.running?).to be_false
    end
  end
end
