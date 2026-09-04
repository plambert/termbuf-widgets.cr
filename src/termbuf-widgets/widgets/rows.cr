module TermBuf::Widgets
  # Where a `VirtualList` gets what it shows.
  #
  # Two questions and no more: how many rows there are, and what row *index*
  # is. A list that draws twenty rows asks twenty times however many there
  # are, which is what lets it show a table nobody could hold in memory.
  #
  # Everything built on the list — a selection list, a tree, a data grid, a
  # combobox — wraps one of these rather than replacing it: a tree flattens
  # its open nodes into rows, a grid answers a record per row, and both stay
  # virtual for free.
  abstract class Rows(T)
    # How many rows there are.
    abstract def size : Int32

    # What row *index* holds. Only ever asked about a row that is showing.
    abstract def row(index : Int32) : T

    # Whether there is nothing to show.
    def empty? : Bool
      size.zero?
    end

    # An array as a source of rows.
    def self.of(items : Array(T)) : Rows(T)
      Held(T).new items
    end

    # A pair of blocks as one, for a source that is computed rather than held.
    def self.from(count : Proc(Int32), fetch : Proc(Int32, T)) : Rows(T)
      Asked(T).new count, fetch
    end

    # Rows held in an array.
    class Held(T) < Rows(T)
      # What is being shown.
      property items : Array(T)

      def initialize(@items : Array(T))
      end

      def size : Int32
        @items.size
      end

      def row(index : Int32) : T
        @items[index]
      end
    end

    # Rows answered by a pair of blocks, which is what a source too large to
    # hold looks like.
    class Asked(T) < Rows(T)
      def initialize(@count : Proc(Int32), @fetch : Proc(Int32, T))
      end

      def size : Int32
        @count.call
      end

      def row(index : Int32) : T
        @fetch.call index
      end
    end
  end
end
