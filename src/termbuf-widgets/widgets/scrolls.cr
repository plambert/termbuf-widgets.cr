module TermBuf::Widgets
  # What a `Scrollbar` needs of the thing it is attached to.
  #
  # A `Scrollable` is one of these because it is a window over child widgets. A
  # `VirtualList` is one because it is a window over rows it never builds
  # widgets for. Neither knows about the other, and a scrollbar does not have
  # to: what it wants is how much there is, how much is showing, and how far in
  # the window sits.
  module Scrolls
    # Cells the content comes to.
    abstract def content_size : {Int32, Int32}

    # Cells there are to show it in.
    abstract def viewport_size : {Int32, Int32}

    # How far in the window sits.
    abstract def scroll_x : Int32

    # :ditto:
    abstract def scroll_y : Int32

    # Moves the window, stopping at either end.
    abstract def scroll_by(dx : Int32, dy : Int32) : Nil

    # Whether the window cuts that axis, which is what says a scrollbar for it
    # is worth having.
    abstract def clip_x? : Bool

    # :ditto:
    abstract def clip_y? : Bool

    # How many cells one notch of the wheel moves.
    def wheel : Int32
      3
    end

    # The furthest the content can be scrolled before its end is in view.
    def max_scroll : {Int32, Int32}
      size = content_size
      room = viewport_size

      {Math.max(size[0] - room[0], 0), Math.max(size[1] - room[1], 0)}
    end

    # Answers a wheel notch, and says whether it was one.
    #
    # A window that only clips sideways takes the ordinary up and down wheel
    # as well, because that is the wheel most pointers have.
    def scroll_wheel(event : Events::Mouse) : Bool
      sideways = clip_x? && !clip_y?

      case event.button
      when .wheel_up?    then sideways ? scroll_by(-wheel, 0) : scroll_by(0, -wheel)
      when .wheel_down?  then sideways ? scroll_by(wheel, 0) : scroll_by(0, wheel)
      when .wheel_left?  then scroll_by(-wheel, 0)
      when .wheel_right? then scroll_by wheel, 0
      else                    return false
      end

      true
    end
  end
end
