module Fixtures
  # An `App` drawing into a `TermBuf::Buffer` instead of a terminal.
  #
  # Nothing here opens a device, so a spec can drive a whole application:
  # send events, pump them, take a frame, and read the screen back.
  class TestApp < TermBuf::Widgets::App
    # What frames are drawn into.
    getter buffer : TermBuf::Buffer

    def initialize(root : TermBuf::Widgets::Widget, columns : Int32 = 30, rows : Int32 = 6,
                   policy : TermBuf::Unicode::WidthPolicy = TermBuf::Unicode::WidthPolicy::DEFAULT)
      buffer = TermBuf::Buffer.new columns, rows
      buffer.policy = policy
      @buffer = buffer

      super TermBuf::BufferSurface.new(buffer), root, TermBuf::Rect.full(columns, rows),
        Channel(TermBuf::Event).new(64), policy
    end

    # What the screen shows, one line per row with the trailing blanks cut.
    def lines : Array(String)
      @buffer.to_text.split('\n').map &.rstrip
    end

    # Grows or shrinks the screen the way a terminal would: the buffer first,
    # then the event that says so.
    def resized(columns : Int32, rows : Int32) : Nil
      previous = TermBuf::ScreenSize.new @buffer.width, @buffer.height
      @buffer.resize columns, rows
      @events.send TermBuf::Events::Resize.new(TermBuf::ScreenSize.new(columns, rows), previous)
    end
  end
end
