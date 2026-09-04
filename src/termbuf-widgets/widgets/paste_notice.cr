require "../widget"
require "./border"

module TermBuf::Widgets
  # A panel saying a paste is arriving, so a long one does not look like a
  # hung application.
  #
  # The driver will not draw this. The buffer belongs to the application, and
  # something writing into it uninvited would have to undraw itself and would
  # fight whatever else was painting. So the decoder reports and this draws:
  # `TermBuf::Events::Pasting` opens it and `TermBuf::Events::Paste` closes it.
  #
  #     when TermBuf::Events::Pasting then notice.arriving event.bytes
  #     when TermBuf::Events::Paste   then notice.finished
  #
  # It floats in the middle of the screen at a `z` above anything an
  # application is likely to use, and is hidden whenever nothing is arriving,
  # so a tree can hold one from the start and leave it alone.
  class PasteNotice < Widget
    # What it says, before the byte count.
    property label : String

    # Bytes collected so far, or `nil` when nothing is arriving.
    getter bytes : Int32? = nil

    # Cells of quiet either side of the label inside the panel.
    PADDING = 4

    # Rows the panel takes, before any border.
    ROWS = 3

    # High enough that an application's own floats sit under it: a paste
    # arriving is the most urgent thing on the screen while it is arriving.
    LAYER = 100

    def initialize(@label : String = "pasting",
                   style : Style = Style::DEFAULT.reverse,
                   border : Border? = nil)
      @style = style
      @border = border
      @hidden = true
      @floating = Layout::Floating.new(
        Layout::Anchor.new(nil, Layout::AttachPoint::Center, Layout::AttachPoint::Center),
        z: LAYER)
    end

    # A paste has been going long enough to be worth mentioning, and has
    # *bytes* so far.
    def arriving(bytes : Int32) : Nil
      @bytes = bytes
      self.hidden = false
      invalidate_layout
    end

    # The paste is over.
    def finished : Nil
      @bytes = nil
      self.hidden = true
    end

    # Whether there is anything to draw.
    def visible? : Bool
      !@bytes.nil?
    end

    # What the panel says, which is the byte count as it grows.
    def text : String
      bytes = @bytes
      return @label unless bytes

      "#{@label} #{bytes} bytes"
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.exact Unicode.string_width(text, policy) + PADDING
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      ROWS
    end

    # Writes the label across the middle of the panel. The ground and the box
    # are the renderer's, from `Widget#style` and `Widget#border`.
    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      label = text
      room = view.width - Unicode.string_width(label, view.policy)
      view.write Math.max(room // 2, 0), view.height // 2, label, Style::DEFAULT.bold
    end
  end
end
