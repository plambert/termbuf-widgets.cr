require "../widget"
require "./scrolls"

module TermBuf::Widgets
  # A widget showing a window onto more than fits in it, and how far in that
  # window has got to.
  #
  # `Table` and `VirtualList` are both one of these: a window over columns and
  # rows, and a window over rows alone. What they share is the position, which is
  # two numbers and has nothing to do with what a row holds.
  #
  # ### Why `Scrolls` is included here
  #
  # Not tidiness. Both of those widgets are generic, and `DataGrid(T) < Table(T)`
  # is a generic class whose superclass is another one.
  #
  # A call on a `Scrolls`-typed variable, which is what `Scrollbar` holds, is
  # dispatched over every type that includes the module. With the include on
  # `Table(T)`, building a `DataGrid(String)` added a member, and the compiler
  # typed `#scroll_y` for it there and then — before `Table(String)` existed to
  # copy `@scroll`'s declaration from, because nothing else in the shard ever
  # names that generic instance. The result was `can't infer the type of instance
  # variable '@scroll' of DataGrid(String)`, and whether it happened came down to
  # whether some earlier file had built a `Table(String)` first. `crystal spec`
  # globs its files in filesystem order, so the suite compiled on one filesystem
  # and not on another. Annotating `@scroll` does not help: the compiler asks for
  # the annotation on `DataGrid(String)`, which is not a thing anyone can write.
  #
  # A non-generic class in the module's place has its instance variables settled
  # once, so no order comes into it. That is also why the position lives here
  # rather than on the widgets: a `Scrolls` method that reads it has to find it on
  # the type the module holds.
  #
  # Crystal 1.21.1. Reported against 0.5.0 of this shard, which has the same
  # shape.
  abstract class Viewport < Widget
    include Scrolls

    # The first row showing.
    getter scroll : Int32 = 0

    # Cells the content is scrolled left by.
    getter offset : Int32 = 0

    # How many cells one notch of the wheel moves.
    property wheel : Int32 = 3

    # Cells the content is scrolled left by.
    def scroll_x : Int32
      @offset
    end

    # The first row showing, which is the same number of cells down.
    def scroll_y : Int32
      @scroll
    end

    # Cells there are to show the content in, which is the box the widget draws
    # in. The same answer for every window, so it is given once here.
    def viewport_size : {Int32, Int32}
      box = content
      {box.width, box.height}
    end

    # Moves the window on either axis, stopping at the ends.
    def scroll_by(dx : Int32, dy : Int32) : Nil
      limit = max_scroll
      @offset = (@offset + dx).clamp 0, limit[0]
      @scroll = (@scroll + dy).clamp 0, limit[1]
    end

    # What the content comes to. Nothing, until a subclass says otherwise:
    # what is in the window is the one part of scrolling this class cannot
    # know.
    #
    # Given a body rather than left abstract because the module dispatches over
    # this class, and a dispatch has nothing to call on an abstract method. No
    # instance of this class exists to run it. The same goes for `#clip_x?` and
    # `#clip_y?`.
    def content_size : {Int32, Int32}
      {0, 0}
    end

    # Whether the window cuts that axis, which is what says a scrollbar for it
    # is worth having. A window cuts rows and not columns until a subclass says
    # otherwise, which is what a list of rows does.
    def clip_x? : Bool
      false
    end

    # :ditto:
    def clip_y? : Bool
      true
    end
  end
end
