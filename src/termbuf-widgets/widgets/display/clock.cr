require "./attached"
require "./readout"

module TermBuf::Widgets
  # The time of day, kept up to date by a timer the application lends it.
  #
  #     clock = Clock.new "%H:%M"
  #     clock.start app
  #
  # ### The boundary, not the interval
  #
  # A clock showing seconds that armed a timer for one second would drift: it
  # would come round a little later every minute, and the second it shows would
  # change at whatever moment it happened to be started. `#interval` instead
  # answers how long is left of the current `#resolution` — the time to the
  # next whole second, or the next whole minute — so the reading changes when
  # the clock on the wall does.
  #
  # ### Where the time comes from
  #
  # `#now` is a block answering the time, and it is `Time.local` unless
  # something says otherwise. A spec hands over one that answers whatever it
  # likes, which is what makes a clock testable without waiting for one:
  #
  #     at = Time.local 2026, 9, 4, 20, 40, 49
  #     clock = Clock.new now: -> { at }
  class Clock < Readout
    include Ticking

    # What a clock shows when nothing says otherwise.
    DEFAULT_FORMAT = "%H:%M:%S"

    # How often it comes round when nothing says otherwise.
    DEFAULT_RESOLUTION = 1.second

    # How the time is written. See `Time::Format` for what the directives mean.
    layout_property format : String = DEFAULT_FORMAT

    # How much of the time the clock shows, which is what it comes round on:
    # one second for a clock showing seconds, one minute for one that does not.
    property resolution : Time::Span = DEFAULT_RESOLUTION

    # Where the time comes from.
    property now : Proc(Time) = -> { Time.local }

    @shown : String = ""

    def initialize(format : String = DEFAULT_FORMAT,
                   resolution : Time::Span = DEFAULT_RESOLUTION,
                   now : Proc(Time)? = nil,
                   align : Unicode::Align = Unicode::Align::Left,
                   style : Style? = nil)
      @format = format
      @resolution = resolution
      @now = now || -> { Time.local }
      @align = align
      @style = style
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fixed 1
      @shown = reading
    end

    # What the clock says, as of its last reading.
    def text : String
      @shown
    end

    # The time as it would be written now, without taking it as the reading.
    def reading : String
      @now.call.to_s @format
    end

    # Takes a fresh reading, saying so when it came out different.
    #
    # The invalidation is the point: `"9:59"` and `"10:00"` are not the same
    # width, and a clock that changed what it drew without saying so would
    # leave whatever sits beside it a cell out.
    def refresh : Nil
      fresh = reading
      return if fresh == @shown

      @shown = fresh
      invalidate_layout
    end

    # Sets the format and takes a fresh reading through it at once, so the
    # widget is never showing the old one.
    def format=(format : String) : String
      return format if @format == format

      previous_def
      refresh
      format
    end

    # ------------------------------------------------------------- ticking

    # Takes a fresh reading, which is all a tick does.
    def tick : Nil
      refresh
    end

    # How long is left of the current `#resolution`. See the class docs.
    def interval : Time::Span
      step = @resolution.total_nanoseconds.to_i64
      return @resolution if step <= 0

      (step - @now.call.to_unix_ns % step).nanoseconds
    end
  end
end
