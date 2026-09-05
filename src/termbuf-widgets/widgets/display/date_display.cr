require "./readout"

module TermBuf::Widgets
  # A date, written the way `Time::Format` writes one.
  #
  #     stamp = DateDisplay.new released_at, "%Y-%m-%d %H:%M"
  #
  # The plainest of the three time widgets and the only one with no clock in
  # it: a date does not change on its own, so there is nothing to refresh. Both
  # the time and the format are layout properties, so changing either says so
  # and the next frame is laid out for the width the new text needs.
  #
  # For a time that moves, `Clock` shows the present and `RelativeTime` shows
  # how far off something is.
  class DateDisplay < Readout
    # What a date shows when nothing says otherwise.
    DEFAULT_FORMAT = "%Y-%m-%d"

    # The time being written.
    layout_property at : Time = Time.local

    # How it is written. See `Time::Format` for what the directives mean.
    layout_property format : String = DEFAULT_FORMAT

    def initialize(at : Time? = nil,
                   format : String = DEFAULT_FORMAT,
                   align : Unicode::Align = Unicode::Align::Left,
                   style : Style? = nil)
      @at = at || Time.local
      @format = format
      @align = align
      @style = style
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fixed 1
    end

    # The date as it is written.
    def text : String
      @at.to_s @format
    end
  end
end
