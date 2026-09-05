module TermBuf::Widgets
  # Where a `Tree` gets what it shows.
  #
  # Four questions, and nothing about screens or rows in any of them: what the
  # top of the tree is, what hangs under a node, whether a node has anything
  # under it at all, and what to write for one.
  #
  # `#leaf?` is asked separately from `#children` on purpose. A source that
  # loads a directory, a table or a page of an API knows whether a node can
  # have children long before it knows what they are, and answering the cheap
  # question means the expensive one is asked only for a node somebody
  # actually opened.
  abstract class Nodes(T)
    # The nodes at the top, in order.
    abstract def roots : Array(T)

    # What hangs under *node*, in order. Asked once per node, the first time
    # it is expanded.
    abstract def children(node : T) : Array(T)

    # Whether *node* can have nothing under it. Asked for every node that is
    # flattened, so it must be cheap.
    abstract def leaf?(node : T) : Bool

    # What is written for *node*.
    abstract def label(node : T) : String

    # A source built from blocks, for a tree whose nodes are already
    # somebody else's type.
    #
    # *leaf* is optional; without one a node is a leaf when it has no
    # children, which means asking for them. Give one for a source where that
    # is the expensive question.
    def self.from(roots : Array(T),
                  children : Proc(T, Array(T)),
                  label : Proc(T, String),
                  leaf : Proc(T, Bool)? = nil) : Nodes(T)
      Asked(T).new roots, children, label, leaf
    end

    # A source answered by blocks.
    class Asked(T) < Nodes(T)
      def initialize(@roots : Array(T),
                     @children : Proc(T, Array(T)),
                     @label : Proc(T, String),
                     @leaf : Proc(T, Bool)? = nil)
      end

      def roots : Array(T)
        @roots
      end

      def children(node : T) : Array(T)
        @children.call node
      end

      def leaf?(node : T) : Bool
        asked = @leaf
        return asked.call node if asked

        children(node).empty?
      end

      def label(node : T) : String
        @label.call node
      end
    end
  end
end
