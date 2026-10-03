module TermBuf::Widgets
  # What a `Scrollbar` needs of the thing it is attached to.
  #
  # A `Scrollable` is one of these because it is a window over child widgets. A
  # `VirtualList` is one because it is a window over rows it never builds
  # widgets for. Neither knows about the other, and a scrollbar does not have
  # to: what it wants is how much there is, how much is showing, and how far in
  # the window sits.
  module Scrolls
    # How many rows to hold between the selection and the edge of the window
    # when it is brought into view.
    #
    # It is a value so that a window can be given one in a word, and so that two
    # of them compare equal when they say the same thing. It says how many rows
    # to keep for a window of a given height, not how many: the same share of a
    # taller window is more rows.
    record Margin, fixed : Int32, fraction : Float64 do
      # No margin. The window moves as little as it takes to show the row, which
      # leaves the selection on the last row it can reach.
      def self.none : Margin
        new 0, 0.0
      end

      # *count* rows at each end. A negative count is none.
      def self.rows(count : Int32) : Margin
        new Math.max(count, 0), 0.0
      end

      # *fraction* of the window at each end, so `0.25` holds the selection in
      # the middle half. A fraction outside 0 to 1, or one that is not a number,
      # is held to that range.
      def self.share(fraction : Float64) : Margin
        new 0, fraction.nan? ? 0.0 : fraction.clamp(0.0, 1.0)
      end

      # The rows to keep at each end of a window *room* rows tall.
      #
      # The answer is at most `(room - 1) // 2`, which leaves the selected row
      # and a margin on each side inside the window. A window of one row, or
      # none, has no margin. A share is rounded down, so a share of a small
      # window is nothing until it comes to a whole row.
      def rows_for(room : Int32) : Int32
        return 0 if room <= 1

        wanted = Math.max(@fixed, (room * @fraction).to_i)
        Math.min wanted, (room - 1) // 2
      end
    end

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

    # The first row a window should show so that row *index* is in view and no
    # nearer either edge than *margin* allows, for a window *room* rows tall.
    #
    # The answer is not held to what the content has. The caller clamps it, which
    # is what lets the selection reach the first and last row: at either end
    # there is nothing further to scroll to, so the margin gives way.
    #
    # The window stays where it is when the row is already far enough in. Only
    # a row that has come within the margin of an edge moves it.
    def top_for(index : Int32, room : Int32, margin : Margin) : Int32
      keep = margin.rows_for room
      top = scroll_y
      top = index - room + 1 + keep if index > top + room - 1 - keep
      top = index - keep if index < top + keep
      top
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
