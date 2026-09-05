require "./attached"
require "./readout"

module TermBuf::Widgets
  # How long ago something was, or how long until it is, in words.
  #
  #     age = RelativeTime.new file.modification_time
  #     age.start app
  #
  # Reads "3 minutes ago" for a time behind and "in 2 hours" for one ahead,
  # with the unit chosen so that the number stays small: seconds under a
  # minute, minutes under an hour, then hours, days, weeks, months and years.
  # Anything inside `RECENT` of now is `#just_now` instead, because "2 seconds
  # ago" is a number nobody asked for.
  #
  # ### The refresh slows down as it ages
  #
  # A minute old, the text changes every second and the timer is armed for one.
  # An hour old it changes every minute; a day old, every hour; past that, once
  # a day. `Ticking` asks `#interval` again after every tick, so the widget has
  # nothing to do about this beyond answering the span its own age calls for.
  # A row of a hundred of these costs a hundred timers a day rather than a
  # hundred a second.
  #
  # ### Where the time comes from
  #
  # `#now` is a block answering the present, `Time.local` unless something says
  # otherwise, so a spec can put the widget at any age it likes.
  class RelativeTime < Readout
    include Ticking

    # Anything this close to now is `#just_now` rather than a count.
    RECENT = 5.seconds

    # Days in the month and the year this counts by. Neither is a calendar
    # month or a leap year: "3 months ago" is an approximation, and one drawn
    # from the real length of the intervening months would still be one.
    MONTH =  30
    YEAR  = 365

    # The time being described.
    layout_property at : Time = Time.local

    # What is said for a time inside `RECENT` of now.
    layout_property just_now : String = "just now"

    # Where the present comes from.
    property now : Proc(Time) = -> { Time.local }

    @shown : String = ""

    def initialize(at : Time? = nil,
                   just_now : String = "just now",
                   now : Proc(Time)? = nil,
                   align : Unicode::Align = Unicode::Align::Left,
                   style : Style? = nil)
      @now = now || -> { Time.local }
      @at = at || @now.call
      @just_now = just_now
      @align = align
      @style = style
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fixed 1
      @shown = reading
    end

    # How *at* reads against *from*.
    def self.describe(at : Time, from : Time, just_now : String = "just now") : String
      gap = at - from
      ahead = gap > Time::Span.zero
      span = ahead ? gap : -gap
      return just_now if span < RECENT

      ahead ? "in #{amount span}" : "#{amount span} ago"
    end

    # *span* as a count and a unit, with the unit chosen to keep the count
    # small.
    def self.amount(span : Time::Span) : String
      seconds = span.total_seconds
      days = span.total_days

      return count span.total_seconds.to_i, "second" if seconds < 60
      return count span.total_minutes.to_i, "minute" if seconds < 3600
      return count span.total_hours.to_i, "hour" if days < 1
      return count days.to_i, "day" if days < 7
      return count (days / 7).to_i, "week" if days < MONTH
      return count (days / MONTH).to_i, "month" if days < YEAR

      count (days / YEAR).to_i, "year"
    end

    # *amount* of *unit*, pluralised.
    def self.count(amount : Int32, unit : String) : String
      amount == 1 ? "1 #{unit}" : "#{amount} #{unit}s"
    end

    # What it says, as of its last reading.
    def text : String
      @shown
    end

    # How it would read now, without taking it as the reading.
    def reading : String
      RelativeTime.describe @at, @now.call, @just_now
    end

    # Takes a fresh reading, saying so when it came out different: "9 minutes
    # ago" and "10 minutes ago" are not the same width.
    def refresh : Nil
      fresh = reading
      return if fresh == @shown

      @shown = fresh
      invalidate_layout
    end

    def at=(at : Time) : Time
      return at if @at == at

      previous_def
      refresh
      at
    end

    # ------------------------------------------------------------- ticking

    # Takes a fresh reading, which is all a tick does.
    def tick : Nil
      refresh
    end

    # How long until the text could next change. See the class docs.
    def interval : Time::Span
      gap = @at - @now.call
      span = gap > Time::Span.zero ? gap : -gap

      return 1.second if span < 1.minute
      return 1.minute if span < 1.hour
      return 1.hour if span < 1.day

      1.day
    end
  end
end
